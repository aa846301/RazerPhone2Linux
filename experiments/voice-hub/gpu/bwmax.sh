#!/bin/bash
# Build and run cl_bwmax with the GPU pinned at 710 MHz (restored on exit); also a CPU read-bandwidth reference.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/gpu || exit 1
gcc -O2 -o cl_bwmax cl_bwmax.c -lOpenCL || exit 1
gcc -O3 -march=armv8.2-a -pthread -o cpu_bw cpu_bw.c || exit 1
DF=/sys/class/devfreq/5000000.gpu
min0=$(cat $DF/min_freq)
restore() { echo $min0 | sudo tee $DF/min_freq >/dev/null; }
trap restore EXIT
echo 710000000 | sudo tee $DF/min_freq >/dev/null
echo "gpu cur_freq $(cat $DF/cur_freq)"
./cl_bwmax "$@"
echo "gpu cur_freq after $(cat $DF/cur_freq), max temp $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -n 1)"
echo "== CPU reference"
taskset -c 4-7 ./cpu_bw 4
taskset -c 0-7 ./cpu_bw 8
