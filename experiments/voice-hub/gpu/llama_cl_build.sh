#!/bin/bash
# Rebuild llama.cpp OpenCL backends against rusticl: build-cl (generic kernels) and build-cla (Adreno kernels).
exec > /tmp/llama-cl-build.log 2>&1
cd ~/voice/llama.cpp || exit 1
python3 ~/voice/gpu/patch_llama_subgroups.py ggml/src/ggml-opencl/ggml-opencl.cpp || exit 1
python3 ~/voice/gpu/patch_llama_rusticl_defs.py ggml/src/ggml-opencl/ggml-opencl.cpp || exit 1
bash ~/voice/gpu/patch_llama_kernels_rusticl.sh
cmake -B build-cl -DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF -DLLAMA_CURL=OFF -DCMAKE_BUILD_TYPE=Release
nice cmake --build build-cl -j6 --target llama-bench llama-cli test-backend-ops
echo "build-cl exit=$?"
if [ -z "$ONLY_CL" ]; then
cmake -B build-cla -DGGML_OPENCL=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=ON -DLLAMA_CURL=OFF -DCMAKE_BUILD_TYPE=Release
nice cmake --build build-cla -j6 --target llama-bench test-backend-ops
echo "build-cla exit=$?"
fi
