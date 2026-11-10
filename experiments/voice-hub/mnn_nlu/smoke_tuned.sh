#!/bin/bash
# smoke.sh with CPU performance governor + deep idle disabled (restored on exit), to see the CPU-frequency effect.
gov0=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor)
restore() {
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 0 | sudo tee $s/disable >/dev/null; done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $gov0 | sudo tee $p/scaling_governor >/dev/null; done
}
trap restore EXIT
for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 1 | sudo tee $s/disable >/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance | sudo tee $p/scaling_governor >/dev/null; done
bash ~/voice/mnn_nlu/smoke.sh 2>&1 | grep -E '^\{"text'
