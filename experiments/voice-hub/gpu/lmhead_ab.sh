#!/bin/bash
# A/B the wide-GEMV (lm_head) split in the real model: default SB=1,SC=4 vs SB=8,SC=2. Tuned CPU, restored on exit.
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
run() {  # $1 label, $2 model, $3 precision, rest: env
  local label=$1 m=$2 c=$3; shift 3
  rm -f tmp/mnn_cachefile.bin
  env "$@" timeout 900 taskset -c 4-7 ./llm_bench -m $HOME/voice/models/mnn/$m/config.json -a opencl -t 4 -c $c -p 0 -n 8 -rep 1 -load false > /dev/null 2>&1
  r=$(env "$@" timeout 900 taskset -c 4-7 ./llm_bench -m $HOME/voice/models/mnn/$m/config.json -a opencl -t 4 -c $c -p 0 -n 32 -rep 3 -load false 2>&1 | grep -E 'tg32' | awk -F'|' '{gsub(/ /,"",$8); printf "%s ", $8}')
  echo "$label $m c=$c: tg32=$r (temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1))"
  sleep 8
}
for c in 2 1; do
  run "wide SB1/SC4" Qwen3.5-0.8B-MNN $c MNN_RAZER_GEMV=1
  run "wide SB8/SC2" Qwen3.5-0.8B-MNN $c MNN_RAZER_GEMV_SB_BIG=8 MNN_RAZER_GEMV_SC_BIG=2
  run "wide SB4/SC4" Qwen3.5-0.8B-MNN $c MNN_RAZER_GEMV_SB_BIG=4 MNN_RAZER_GEMV_SC_BIG=4
done
