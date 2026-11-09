#!/bin/bash
# Isolate where OpenCL per-call latency comes from by toggling one power knob at a time.
# All knobs are restored at the end.
export RUSTICL_ENABLE=freedreno
cd /tmp
G=/sys/class/devfreq/5000000.gpu
gpu_min0=$(cat $G/min_freq)
declare -A gov0
for p in /sys/devices/system/cpu/cpufreq/policy*; do gov0[$p]=$(cat $p/scaling_governor); done

cpuidle() {  # $1 = 0 enable deep states, 1 disable all but state0 (WFI)
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo $1 | sudo tee $s/disable >/dev/null; done
}
cpugov() { for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $1 | sudo tee $p/scaling_governor >/dev/null; done; }
gpumin() { echo $1 | sudo tee $G/min_freq >/dev/null; }
restore() {
  cpuidle 0; gpumin $gpu_min0
  for p in "${!gov0[@]}"; do echo ${gov0[$p]} | sudo tee $p/scaling_governor >/dev/null; done
}
trap restore EXIT

echo "cpuidle states: $(cat /sys/devices/system/cpu/cpu4/cpuidle/state*/name | tr '\n' ' ')"
echo "exit latency us: $(cat /sys/devices/system/cpu/cpu4/cpuidle/state*/latency | tr '\n' ' ')"
run() {
  echo "== $1"
  ./cl_launch | grep tiny
  ./cl_breakdown sync | grep -E 'SUBMIT->START|wall'
}
restore
run "baseline (schedutil, deep idle on, gpu min 257MHz)"
cpuidle 1; run "+ CPU deep idle OFF"; cpuidle 0
cpugov performance; run "+ CPU governor performance"; cpugov schedutil
gpumin 710000000; run "+ GPU pinned 710MHz"; gpumin $gpu_min0
cpuidle 1; cpugov performance; gpumin 710000000; run "ALL three"
