#!/bin/bash
# Numerical correctness: CPU (reference trajectory) vs GPU original kernels vs GPU razer kernels.
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/mnn/MNN-3.6.2/build
printf '%s\n' '把客廳主燈調暗一點，然後把冷氣設成二十六度。請只輸出JSON。' > /tmp/lp1.txt
printf '%s\n' '請用繁體中文簡短介紹台灣的地理環境。' > /tmp/lp2.txt
for M in Qwen3.5-0.8B-text Qwen3-1.7B-MNN; do
  D=$HOME/voice/models/mnn/$M
  for p in lp1 lp2; do
    for mode in orig razer; do
      if [ $mode = orig ]; then E="MNN_RAZER_GEMV=0 MNN_RAZER_GDR=0"; else E="MNN_RAZER_GEMV=1 MNN_RAZER_GDR=1"; fi
      rm -f tmp/mnn_cachefile.bin
      r=$(env $E timeout 1500 ./llm_logits_diff $D/config-cpu.json $D/config-opencl.json /tmp/$p.txt 48 2>&1 | grep -E '^summary|^distribution' | tr '\n' ' ')
      echo "$M $p CPU-vs-GPU($mode): $r"
    done
  done
done
