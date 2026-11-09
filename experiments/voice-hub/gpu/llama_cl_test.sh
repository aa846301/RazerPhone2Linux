#!/bin/bash
# llama.cpp OpenCL on rusticl: correctness of key ops (test-backend-ops vs CPU), then decode speed vs MNN.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
export GGML_OPENCL_RUSTICL_ADRENO=1 IR3_SHADER_DEBUG=thread64
cd ~/voice/llama.cpp || exit 1
B=${1:-build-cl}
if [ -z "$SKIP_OPS" ]; then
for op in MUL_MAT RMS_NORM ROPE SOFT_MAX GET_ROWS ADD MUL GATED_DELTA_NET SSM_CONV FLASH_ATTN_EXT CPY GLU; do
  r=$(timeout 2400 ./$B/bin/test-backend-ops -o $op -b GPUOpenCL 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  printf "%-16s OK=%-5s FAIL=%-4s unsupported=%-5s %s\n" $op "$(echo "$r" | grep -cE ': OK *$')" "$(echo "$r" | grep -cE ': FAIL')" \
    "$(echo "$r" | grep -c 'not supported')" "$(echo "$r" | grep -E 'tests passed' | head -1 | xargs)"
  echo "$r" | grep -E ': FAIL' | head -4 | cut -c1-160
done
fi
gov0=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor)
restore() {
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 0 | sudo tee $s/disable >/dev/null; done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $gov0 | sudo tee $p/scaling_governor >/dev/null; done
}
trap restore EXIT
for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 1 | sudo tee $s/disable >/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance | sudo tee $p/scaling_governor >/dev/null; done
echo "== llama-bench GPU (OpenCL, all layers offloaded), tuned CPU"
for m in Qwen3.5-0.8B-Q4_0 Qwen3-1.7B-Q4_0; do
  timeout 1500 taskset -c 4-7 ./$B/bin/llama-bench -m ~/voice/models/llm/$m.gguf -ngl 99 -t 4 -p 256 -n 32 -r 2 2>&1 | \
    grep -E "^\|" | sed 's/\x1b\[[0-9;]*m//g'
  echo "temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1)"
  sleep 10
done
