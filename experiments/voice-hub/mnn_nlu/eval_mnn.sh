#!/bin/bash
# Phone: NLU accuracy + latency with the MNN prefix-cached server (Qwen3-1.7B, GPU OpenCL fp16) as the LLM.
# Default CPU power settings (what production would see). Stops the server on exit.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/mnn_nlu
M=${MODEL:-$HOME/voice/models/mnn/Qwen3-1.7B-MNN/config.json}
EXTRA=${EXTRA:-'{"backend_type":"opencl","precision":"low","thread_num":4}'}
BACKEND=${BACKEND:-rules+slots-c}
python3 mnn_openai_server.py ./mnn_nlu_worker "$M" "$EXTRA" 8091 > /tmp/mnn_server.log 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
for i in $(seq 1 120); do grep -q "serving on" /tmp/mnn_server.log && break; sleep 1; done
grep "serving on" /tmp/mnn_server.log || { tail -5 /tmp/mnn_server.log; exit 1; }
cd ~/voice
for t in tests tests-holdout tests-user tests-web; do
  echo "== $t ($BACKEND)"
  python3 nlu.py eval --backend "$BACKEND" --url http://127.0.0.1:8091 --tests "$t.jsonl" --out "/tmp/nlu-mnn-$t.json" 2>&1 | tail -6
done
