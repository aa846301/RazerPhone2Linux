#!/bin/bash
# MNN GPU decode/prefill speed with the hub UI running (idle, dimmed) -- compare against 25.6 tok/s baseline.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/mnn/MNN-3.6.2/build
gov0=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor)
restore() {
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 0 | sudo tee $s/disable >/dev/null; done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $gov0 | sudo tee $p/scaling_governor >/dev/null; done
}
trap restore EXIT
for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 1 | sudo tee $s/disable >/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance | sudo tee $p/scaling_governor >/dev/null; done
echo "hub-ui running: $(pgrep -x hub-ui >/dev/null && echo yes || echo no), backlight $(cat /sys/class/backlight/backlight/brightness)"
M=$HOME/voice/models/mnn/Qwen3.5-0.8B-MNN/config.json
rm -f tmp/mnn_cachefile.bin
timeout 900 taskset -c 4-7 ./llm_bench -m $M -a opencl -t 4 -c 2 -p 0 -n 8 -rep 1 -load false >/dev/null 2>&1
timeout 900 taskset -c 4-7 ./llm_bench -m $M -a opencl -t 4 -c 2 -p 256 -n 32 -rep 2 -load false 2>&1 | grep -E 'pp256|tg32' | awk -F'|' '{gsub(/ /,"",$7); gsub(/ /,"",$8); printf "%s=%s ", $7, $8}'
echo
