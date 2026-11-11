"""Minimal OpenAI-compatible /v1/chat/completions front for mnn_nlu_worker (prefix KV reuse), so nlu.py's
llama-server backends can point at MNN unchanged. `response_format` / grammar is NOT supported by MNN and is
ignored; the reply carries llama.cpp-style "timings" (prompt_n, predicted_n, prompt_ms, predicted_ms).

usage: python3 mnn_openai_server.py <worker binary> <model config.json> '<extra config json>' [port]"""
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STARTED = time.time()

worker_bin, config, extra = sys.argv[1:4]
port = int(sys.argv[4]) if len(sys.argv) > 4 else 8091
proc = subprocess.Popen([worker_bin, config, extra], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        text=True, encoding="utf-8", bufsize=1)
lock = threading.Lock()
while True:
    ln = proc.stdout.readline()
    if not ln:
        sys.exit("worker exited during load")
    if ln.strip().startswith("{") and json.loads(ln).get("ready"):
        break
print(f"mnn worker ready, serving on :{port}", flush=True)


def ask(messages, max_tokens):
    req = json.dumps({"messages": [{"role": m["role"], "content": m["content"]} for m in messages],
                      "max_tokens": int(max_tokens)}, ensure_ascii=False)
    with lock:
        proc.stdin.write(req + "\n")
        proc.stdin.flush()
        while True:
            ln = proc.stdout.readline()
            if not ln:
                raise RuntimeError("worker exited")
            ln = ln.strip()
            if ln.startswith("{"):
                return json.loads(ln)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # "started" lets clients notice a restart (the worker's prefix KV cache is empty again).
        self._send(200, {"status": "ok", "started": STARTED})

    def do_POST(self):
        if not self.path.endswith("/chat/completions"):
            return self._send(404, {"error": "not found"})
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        r = ask(body["messages"], body.get("max_tokens", 200))
        if "error" in r:
            return self._send(400, r)
        self._send(200, {
            "choices": [{"index": 0, "message": {"role": "assistant", "content": r["text"]}, "finish_reason": "stop"}],
            "timings": {"prompt_n": r["prompt_tokens"], "cache_n": r["cached_tokens"], "predicted_n": r["gen_tokens"],
                        "prompt_ms": r["prefill_ms"], "predicted_ms": r["decode_ms"], "wall_ms": r["wall_ms"],
                        "reused": r["reused"]},
        })


ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
