#!/bin/bash
# Dump ir3 disassembly for one GEMV config/mode: gemv_disasm.sh <cl file> <modes> [cfg index] [shape index]
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/gpu || exit 1
gcc -O2 -o gemv_exp_bench gemv_exp_bench.c -lOpenCL -lm || exit 1
for m in $(echo "$2" | grep -o .); do
  ONLY_CFG=${3:-0} ONLY_SHAPE=${4:-0} IR3_SHADER_DEBUG=disasm ./gemv_exp_bench "$1" 3 $m > /tmp/dis_$m.txt 2>&1
  echo "=== mode $m"
  grep -E "mode $m" /tmp/dis_$m.txt
  grep -iE "max_reg|instructions|nops|waves|stp|ldp|spill|fullreg|halfreg|; [a-z]+:" /tmp/dis_$m.txt | grep -v "^ *[0-9]" | sort | uniq -c | sort -rn | head -25
done
