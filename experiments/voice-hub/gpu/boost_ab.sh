#!/bin/bash
# A/B the 2.8 GHz big-core boost OPP (cpufreq/boost) on MNN CPU and GPU decode/prefill. Restores everything on exit.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/mnn/MNN-3.6.2/build
B=/sys/devices/system/cpu/cpufreq/boost
boost0=$(cat $B); gov0=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor)
restore() {
  echo $boost0 | sudo tee $B >/dev/null
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 0 | sudo tee $s/disable >/dev/null; done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $gov0 | sudo tee $p/scaling_governor >/dev/null; done
}
trap restore EXIT
for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 1 | sudo tee $s/disable >/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance | sudo tee $p/scaling_governor >/dev/null; done
M=$HOME/voice/models/mnn/Qwen3.5-0.8B-MNN/config.json
for bo in 0 1; do
  echo $bo | sudo tee $B >/dev/null; sleep 2
  echo "== boost=$bo big-core cur=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq) max=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq)"
  for a in cpu opencl; do
    c=2; [ $a = cpu ] && c=2
    rm -f tmp/mnn_cachefile.bin
    timeout 900 taskset -c 4-7 ./llm_bench -m $M -a $a -t 4 -c $c -p 0 -n 8 -rep 1 -load false >/dev/null 2>&1
    r=$(timeout 900 taskset -c 4-7 ./llm_bench -m $M -a $a -t 4 -c $c -p 256 -n 32 -rep 2 -load false 2>&1 | grep -E 'pp256|tg32' | awk -F'|' '{gsub(/ /,"",$7); gsub(/ /,"",$8); printf "%s=%s ", $7, $8}')
    echo "  $a: $r (temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1))"
    sleep 15
  done
done
