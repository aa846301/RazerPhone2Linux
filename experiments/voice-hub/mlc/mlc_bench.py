"""Phone benchmark for an MLC-LLM model lib: prefill and decode speed via streaming timestamps, plus engine metrics.
usage: python mlc_bench.py <model_dir> <model_lib.so> <device: opencl|vulkan> [decode_tokens]"""
import json
import sys
import time

from mlc_llm import MLCEngine
from mlc_llm.serve.config import EngineConfig

model, lib, device = sys.argv[1:4]
n_decode = int(sys.argv[4]) if len(sys.argv) > 4 else 64

t0 = time.time()
engine = MLCEngine(model=model, model_lib=lib, device=device, mode="local",
                   engine_config=EngineConfig(max_num_sequence=1, max_total_sequence_length=4096,
                                              prefill_chunk_size=256))
print(f"load {time.time() - t0:.1f}s", flush=True)

PROMPT_LONG = ("請把客廳的燈打開，然後把冷氣調到二十六度，順便把窗簾關一半。" * 12)
PROMPT_SHORT = "用一句話介紹台灣。"


def run(prompt, max_tokens, label):
    times = []
    text = []
    t_start = time.time()
    for chunk in engine.chat.completions.create(
            messages=[{"role": "user", "content": prompt}], max_tokens=max_tokens, temperature=0.0,
            stream=True, extra_body={"debug_config": {"ignore_eos": True}}):
        now = time.time()
        for c in chunk.choices:
            if c.delta.content:
                times.append(now)
                text.append(c.delta.content)
    ttft = times[0] - t_start if times else float("nan")
    dec = (len(times) - 1) / (times[-1] - times[0]) if len(times) > 2 else float("nan")
    print(f"[{label}] chunks={len(times)} ttft={ttft:.3f}s decode~{dec:.2f} tok/s", flush=True)
    print("   text:", "".join(text)[:80].replace("\n", " "), flush=True)


run(PROMPT_SHORT, 16, "warmup")
run(PROMPT_SHORT, n_decode, "short")
run(PROMPT_LONG, n_decode, "long-prompt")
try:
    m = engine.metrics()
    keep = {k: v for k, v in (m.items() if hasattr(m, "items") else json.loads(str(m)).items())
            if any(s in k for s in ("prefill", "decode", "tokens_per", "ttft", "tpot"))}
    print("metrics:", json.dumps(keep, ensure_ascii=False)[:800], flush=True)
except Exception as e:  # metrics API differs between versions
    print("metrics unavailable:", e)
engine.terminate()
