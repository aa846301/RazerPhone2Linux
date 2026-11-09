#!/bin/bash
# ALU throughput microbench at 710 MHz (restored on exit), plus the ir3 opcode mix of each kernel.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/gpu || exit 1
gcc -O2 -o alu_tp alu_tp.c -lOpenCL || exit 1
DF=/sys/class/devfreq/5000000.gpu; min0=$(cat $DF/min_freq)
trap 'echo $min0 | sudo tee $DF/min_freq >/dev/null' EXIT
echo 710000000 | sudo tee $DF/min_freq >/dev/null
./alu_tp alu_tp.cl
MESA_SHADER_CACHE_DISABLE=true IR3_SHADER_DEBUG=disasm ./alu_tp alu_tp.cl > /tmp/alu_dis.txt 2>&1
sed 's/^MESA: info: //' /tmp/alu_dis.txt | grep -E "^; CL prog [0-9]+/1: [0-9]+ instr|cat[0-9] " | grep -vE " (1[0-9]|[2-9][0-9]|[0-9]) instr" | head -12
