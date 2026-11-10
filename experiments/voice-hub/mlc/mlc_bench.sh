#!/bin/bash
# Phone: run mlc_bench.py with the tuned CPU power settings used for the MNN numbers (restored on exit),
# then report any GPU hangs logged during the run.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors
export MLC28_ROOT=$HOME/voice/mlc-llm MLC28_VENV=$HOME/voice/mlc-venv
. ~/voice/mlc/mlc28_env.sh
export LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH
M=${1:-$HOME/voice/models/mlc/m28-qwen35-0.8b-q4f16_1}
DEV=${2:-opencl}
gov0=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor)
restore() {
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 0 | sudo tee $s/disable >/dev/null; done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $gov0 | sudo tee $p/scaling_governor >/dev/null; done
}
trap restore EXIT
for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 1 | sudo tee $s/disable >/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance | sudo tee $p/scaling_governor >/dev/null; done
mark=$(sudo dmesg | wc -l)
timeout 1800 taskset -c 4-7 python ~/voice/mlc/mlc_bench.py "$M" "$M/lib-$DEV.so" "$DEV" 64 2>&1 | \
  grep -vE "arm_aprofile|Cannot parse target" | tail -25
echo "max temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1)"
echo "GPU hangs during run: $(sudo dmesg | tail -n +$((mark + 1)) | grep -c 'hangcheck')"
