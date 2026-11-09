#!/bin/bash
# Separate MNN build with per-kernel GPU timing (event profiling).
exec > /tmp/mnn-prof-build.log 2>&1
cd ~/voice/mnn/MNN-3.6.2
cmake -B build-prof -DCMAKE_BUILD_TYPE=Release -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_SUPPORT_TRANSFORMER_FUSE=ON \
  -DMNN_CPU_WEIGHT_DEQUANT_GEMM=ON -DMNN_ARM82=ON -DMNN_OPENCL=ON -DMNN_SEP_BUILD=OFF -DMNN_GPU_TIME_PROFILE=ON
nice cmake --build build-prof -j6 --target llm_bench llm_demo
echo "exit=$?"
