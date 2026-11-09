#!/bin/bash
# razer GEMV with CPU big cluster pinned (performance governor) and deep idle off, both restored on exit.
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
for m in Qwen3.5-0.8B-MNN Qwen3-1.7B-MNN; do
  rm -f tmp/mnn_cachefile.bin
  timeout 900 taskset -c 4-7 ./llm_bench -m $HOME/voice/models/mnn/$m/config.json -a opencl -t 4 -c 2 -p 0 -n 8 -rep 1 -load false > /dev/null 2>&1
  r=$(timeout 900 taskset -c 4-7 ./llm_bench -m $HOME/voice/models/mnn/$m/config.json -a opencl -t 4 -c 2 -p 256 -n 32 -rep 2 -load false 2>&1 | grep -E 'pp256|tg32' | awk -F'|' '{gsub(/ /,"",$7); gsub(/ /,"",$8); printf "%s=%s ", $7, $8}')
  echo "razer+tunedCPU $m: $r (temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1))"
  sleep 10
done
