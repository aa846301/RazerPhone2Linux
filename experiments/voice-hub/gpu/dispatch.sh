#!/bin/bash
# Per-dispatch overhead with default power settings, then with CPU performance governor + no deep idle (restored).
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/gpu || exit 1
gcc -O2 -o cl_dispatch cl_dispatch.c -lOpenCL || exit 1
gov0=$(cat /sys/devices/system/cpu/cpufreq/policy4/scaling_governor)
DF=/sys/class/devfreq/5000000.gpu; min0=$(cat $DF/min_freq)
restore() {
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 0 | sudo tee $s/disable >/dev/null; done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do echo $gov0 | sudo tee $p/scaling_governor >/dev/null; done
  echo $min0 | sudo tee $DF/min_freq >/dev/null
}
trap restore EXIT
echo 710000000 | sudo tee $DF/min_freq >/dev/null
echo "== default CPU power settings (GPU pinned 710 MHz)"
taskset -c 4-7 ./cl_dispatch 2000
for s in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]; do echo 1 | sudo tee $s/disable >/dev/null; done
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance | sudo tee $p/scaling_governor >/dev/null; done
echo "== CPU performance + no deep idle"
taskset -c 4-7 ./cl_dispatch 2000 | grep -v extensions
