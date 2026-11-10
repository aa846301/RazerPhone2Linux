// MNN LLM worker with prefix KV reuse for the voice-hub NLU.
//
// Protocol (stdin/stdout, one JSON object per line):
//   in : {"messages":[{"role":"system","content":"..."},...,{"role":"user","content":"..."}], "max_tokens":200}
//   out: {"text":"...","prompt_tokens":N,"cached_tokens":H,"gen_tokens":M,"prefill_ms":x,"decode_ms":y,"reused":true}
//
// Every request is split into a prefix (all messages before the last user message, plus the opening of the
// last user turn) and a suffix (the last user message + assistant header). If the prefix text equals the cached
// one, the KV entries after the prefix are erased (Llm::eraseHistory) and only the suffix is prefilled; otherwise
// the cache is rebuilt. For voice commands the prefix (system prompt + few-shot examples) is the bulk of the
// prompt, so each request only prefills ~10-30 tokens.
//
// Usage: mnn_nlu_worker <model config.json> [extra config json, e.g. {"backend_type":"opencl","precision":"low"}]
#include <llm/llm.hpp>
#include <rapidjson/document.h>

#include <chrono>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

using MNN::Transformer::ChatMessages;
using MNN::Transformer::Llm;

static std::string jesc(const std::string& s) {
    std::string o;
    o.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"': o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if (c < 0x20) {
                    char b[8];
                    snprintf(b, sizeof b, "\\u%04x", c);
                    o += b;
                } else {
                    o += (char)c;
                }
        }
    }
    return o;
}

// Qwen3 non-thinking mode: the template's generation prompt is "<|im_start|>assistant\n"; append an empty think
// block exactly like `enable_thinking=False` does in the HF template.
static std::string no_think(std::string p) {
    const std::string tail = "<|im_start|>assistant\n";
    if (p.size() >= tail.size() && p.compare(p.size() - tail.size(), tail.size(), tail) == 0) {
        p += "<think>\n\n</think>\n\n";
    }
    return p;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "usage: mnn_nlu_worker <config.json> [extra-config-json]\n";
        return 2;
    }
    std::unique_ptr<Llm, void (*)(Llm*)> llm(Llm::createLLM(argv[1]), Llm::destroy);
    std::string extra = argc > 2 ? argv[2] : "{}";
    // reuse_kv keeps the KV cache across response() calls; greedy decoding for deterministic parsing.
    llm->set_config("{\"reuse_kv\":true,\"sampler_type\":\"greedy\",\"prompt_cache\":false}");
    llm->set_config(extra);
    if (!llm->load()) {
        std::cerr << "load failed\n";
        return 1;
    }
    std::cerr << "worker ready\n";
    std::cout << "{\"ready\":true}" << std::endl;

    std::string cached_prefix_text;
    std::vector<int> cached_prefix_ids;
    size_t cached_len = 0;  // KV entries covering the prefix

    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        rapidjson::Document doc;
        doc.Parse(line.c_str());
        if (doc.HasParseError() || !doc.HasMember("messages") || !doc["messages"].IsArray()) {
            std::cout << "{\"error\":\"bad request\"}" << std::endl;
            continue;
        }
        int max_tokens = doc.HasMember("max_tokens") && doc["max_tokens"].IsInt() ? doc["max_tokens"].GetInt() : 200;
        ChatMessages msgs;
        for (auto& m : doc["messages"].GetArray()) {
            msgs.emplace_back(m["role"].GetString(), m["content"].GetString());
        }
        if (msgs.empty() || msgs.back().first != "user") {
            std::cout << "{\"error\":\"last message must be user\"}" << std::endl;
            continue;
        }
        const std::string marker = "\x01\x02MARK\x02\x01";
        ChatMessages marked = msgs;
        marked.back().second = marker;
        std::string full = no_think(llm->apply_chat_template(msgs));
        std::string with_marker = llm->apply_chat_template(marked);
        size_t cut = with_marker.find(marker);
        std::string prefix_text = cut == std::string::npos ? std::string() : with_marker.substr(0, cut);
        std::vector<int> full_ids = llm->tokenizer_encode(full);

        bool reused = false;
        if (!prefix_text.empty() && prefix_text == cached_prefix_text && cached_len > 0 &&
            full_ids.size() > cached_prefix_ids.size() &&
            std::equal(cached_prefix_ids.begin(), cached_prefix_ids.end(), full_ids.begin())) {
            if (llm->getCurrentHistory() > cached_len) llm->eraseHistory(cached_len, 0);
            reused = true;
        } else {
            // (Re)build the prefix cache: prefill the prefix, generate one throwaway token (its KV is not added).
            llm->reset();
            cached_prefix_text = prefix_text;
            cached_prefix_ids = llm->tokenizer_encode(prefix_text);
            std::ostringstream sink;
            llm->response(cached_prefix_ids, &sink, nullptr, 1);
            cached_len = llm->getCurrentHistory();
            if (cached_len != cached_prefix_ids.size()) {
                // History holds more than the prefix (e.g. the sampled token): trim back to the prefix.
                if (cached_len > cached_prefix_ids.size()) llm->eraseHistory(cached_prefix_ids.size(), 0);
                cached_len = cached_prefix_ids.size();
            }
            if (!std::equal(cached_prefix_ids.begin(), cached_prefix_ids.end(), full_ids.begin())) {
                // Tokenization of prefix+suffix does not split at the prefix boundary: no reuse possible.
                cached_prefix_text.clear();
                cached_len = 0;
                llm->reset();
            }
        }
        std::vector<int> delta;
        if (cached_len > 0) {
            delta.assign(full_ids.begin() + cached_prefix_ids.size(), full_ids.end());
        } else {
            delta = full_ids;
        }
        std::ostringstream os;
        auto t0 = std::chrono::steady_clock::now();
        llm->response(delta, &os, nullptr, max_tokens);
        double wall_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        auto ctx = llm->getContext();
        std::cout << "{\"text\":\"" << jesc(os.str()) << "\",\"prompt_tokens\":" << delta.size()
                  << ",\"cached_tokens\":" << (cached_len > 0 ? cached_prefix_ids.size() : 0)
                  << ",\"gen_tokens\":" << ctx->gen_seq_len << ",\"prefill_ms\":" << ctx->prefill_us / 1000.0
                  << ",\"decode_ms\":" << ctx->decode_us / 1000.0 << ",\"wall_ms\":" << wall_ms
                  << ",\"reused\":" << (reused ? "true" : "false") << "}" << std::endl;
    }
    return 0;
}
