#!/bin/bash
# CPU vs GPU slot-LLM latency with the prefix cache hit, with and without frequency locks.
# Runs a separate MNN server on :8092 per variant (the production one on :8091 is not touched).
# Variants: A cpu | B cpu+bigcore-lock | C gpu | D gpu+bigcore-lock | E gpu+bigcore-lock+gpu-lock
set -u
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/mnn_nlu
M=$HOME/voice/models/mnn/Qwen3-1.7B-MNN/config.json
BIG=/sys/devices/system/cpu/cpufreq/policy4
G=/sys/class/devfreq/5000000.gpu
BIG_MIN0=$(cat $BIG/scaling_min_freq)
G_MIN0=$(cat $G/min_freq)
restore() {
    echo "$BIG_MIN0" | sudo tee $BIG/scaling_min_freq >/dev/null
    echo "$G_MIN0" | sudo tee $G/min_freq >/dev/null
}
trap restore EXIT

run() {  # label backend lock_big lock_gpu
    local label=$1 backend=$2 lockbig=$3 lockgpu=$4
    local extra="{\"backend_type\":\"$backend\",\"precision\":\"low\",\"thread_num\":4}"
    restore
    setsid taskset -c 4-7 python3 mnn_openai_server.py ./mnn_nlu_worker "$M" "$extra" 8092 > /tmp/mnn8092.log 2>&1 &
    local pid=$!
    for i in $(seq 1 180); do grep -q "serving on" /tmp/mnn8092.log && break; sleep 1; done
    [ "$lockbig" = 1 ] && cat $BIG/scaling_max_freq | sudo tee $BIG/scaling_min_freq >/dev/null
    [ "$lockgpu" = 1 ] && cat $G/max_freq | sudo tee $G/min_freq >/dev/null
    echo "== $label: backend=$backend lock_big=$lockbig lock_gpu=$lockgpu (temp $(sort -n /sys/class/thermal/thermal_zone*/temp | tail -1))"
    ~/voice/venv/bin/python ~/hub-agent/llm_freq_bench.py http://127.0.0.1:8092 "$label" 10
    restore
    kill -- -"$pid" 2>/dev/null
    sleep 5
}

run A cpu 0 0
run B cpu 1 0
run C opencl 0 0
run D opencl 1 0
run E opencl 1 1
