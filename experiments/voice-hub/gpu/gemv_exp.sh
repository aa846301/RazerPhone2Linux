#!/bin/bash
# Build + run gemv_exp_bench with the GPU pinned at 710 MHz (restored on exit).
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/gpu || exit 1
gcc -O2 -o gemv_exp_bench gemv_exp_bench.c -lOpenCL -lm || exit 1
DF=/sys/class/devfreq/5000000.gpu
min0=$(cat $DF/min_freq)
trap 'echo $min0 | sudo tee $DF/min_freq >/dev/null' EXIT
echo 710000000 | sudo tee $DF/min_freq >/dev/null
./gemv_exp_bench "${1:-gemv_exp.cl}" "${2:-50}" $3
echo "max temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1)"
