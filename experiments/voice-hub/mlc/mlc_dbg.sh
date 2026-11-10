#!/bin/bash
# Phone: unbuffered short MLC run to see where it stalls. Usage: mlc_dbg.sh [model_dir] [device] [seconds]
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors
export MLC28_ROOT=$HOME/voice/mlc-llm MLC28_VENV=$HOME/voice/mlc-venv
. ~/voice/mlc/mlc28_env.sh
export LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH
M=${1:-$HOME/voice/models/mlc/m28-qwen35-0.8b-q4f16_1}
DEV=${2:-opencl}
timeout "${3:-240}" python -u ~/voice/mlc/mlc_bench.py "$M" "$M/lib-$DEV.so" "$DEV" 32 > /tmp/mlc_dbg.log 2>&1
echo "rc=$?"
grep -vE "arm_aprofile|Cannot parse" /tmp/mlc_dbg.log | tail -25
