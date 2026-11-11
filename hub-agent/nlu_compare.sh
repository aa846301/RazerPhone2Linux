#!/bin/bash
# Compare NLU backends on all test sets with the production LLM stopped (fair timing, no shared memory/CPU).
# A test MNN server (same CPU config as production) runs on :8092; production is restarted at the end.
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
cd ~/voice/mnn_nlu
M=$HOME/voice/models/mnn/Qwen3-1.7B-MNN/config.json
systemctl --user stop razer-mnn-nlu
trap 'systemctl --user start razer-mnn-nlu' EXIT
setsid taskset -c 4-7 python3 mnn_openai_server.py ./mnn_nlu_worker "$M" \
    '{"backend_type":"cpu","precision":"low","thread_num":4}' 8092 > /tmp/mnn8092.log 2>&1 &
PID=$!
for i in $(seq 1 180); do grep -q "serving on" /tmp/mnn8092.log && break; sleep 1; done
cd ~/voice
for B in ${BACKENDS:-rules+rewrite rules+slots-c}; do
    for t in tests tests-holdout tests-user tests-web; do
        python3 nlu.py eval --backend "$B" --url http://127.0.0.1:8092 --tests $t.jsonl \
            --out "/tmp/cmp-$B-$t.json" 2>&1 | grep "SET " | sed "s/^/[$B] /"
    done
done
kill -- -"$PID" 2>/dev/null
