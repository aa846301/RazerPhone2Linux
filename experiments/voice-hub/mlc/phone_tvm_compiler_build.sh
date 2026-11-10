#!/bin/bash
# Phone: build TVM 0.28 compiler libs (no LLVM: models are compiled on the PC) so the mlc_llm python package
# (which imports tvm.te / tvm.relax) can load. Output: ~/voice/mlc-llm/3rdparty/tvm/build/lib
exec > /tmp/phone-tvm-compiler.log 2>&1
set -x
cd ~/voice/mlc-llm/3rdparty/tvm || exit 1
mkdir -p build
cat > build/config.cmake <<'EOF'
set(CMAKE_BUILD_TYPE Release)
set(USE_LLVM OFF)
set(TVM_TIRX_USE_LLVM OFF)
set(HIDE_PRIVATE_SYMBOLS ON)
set(USE_CUDA OFF)
set(USE_METAL OFF)
set(USE_VULKAN ON)
set(USE_OPENCL ON)
set(USE_CUBLAS OFF)
set(USE_CUTLASS OFF)
set(USE_THRUST OFF)
EOF
cd build
cmake .. -G Ninja -DTVM_TIRX_USE_LLVM=OFF || exit 1
nice ninja -j7 || exit 1
ls -la lib/*.so
echo "phone tvm compiler done"
