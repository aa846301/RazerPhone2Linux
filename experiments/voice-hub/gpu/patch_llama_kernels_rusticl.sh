#!/bin/bash
# Source fixes for llama.cpp OpenCL kernels that only compile under Qualcomm's lenient compiler.
cd ~/voice/llama.cpp/ggml/src/ggml-opencl/kernels || exit 1
# implicit address-space conversion (__global uchar* -> __private char*)
sed -i 's|^\(\s*\)char \* scales = src0_s + ib \* 12;|\1global char * scales = (global char *)(src0_s + ib * 12);|' mul_mm_q4_k_f32_l4_lm.cl
grep -n "scales = " mul_mm_q4_k_f32_l4_lm.cl | head -3
