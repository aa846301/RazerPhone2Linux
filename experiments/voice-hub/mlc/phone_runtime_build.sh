#!/bin/bash
# Phone (aarch64): build the MLC-LLM runtime (libmlc_llm + libtvm_runtime, OpenCL + Vulkan) and a Python venv
# that can load cross-compiled model libs. Log: /tmp/mlc-phone-build.log
exec > /tmp/mlc-phone-build.log 2>&1
set -x
cd ~/voice || exit 1
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends git cmake ninja-build python3-dev \
  python3-venv libvulkan-dev spirv-headers ocl-icd-opencl-dev opencl-headers
if [ ! -d mlc-llm ]; then
  git clone --depth 1 https://github.com/mlc-ai/mlc-llm.git || exit 1
fi
cd mlc-llm
git submodule update --init --recursive --depth 1 || exit 1
git log -1 --format='mlc-llm %h %cd'
git -C 3rdparty/tvm log -1 --format='tvm %h %cd'
mkdir -p build && cd build
cat > config.cmake <<'EOF'
set(TVM_SOURCE_DIR 3rdparty/tvm)
set(CMAKE_BUILD_TYPE RelWithDebInfo)
set(USE_CUDA OFF)
set(USE_CUTLASS OFF)
set(USE_CUBLAS OFF)
set(USE_ROCM OFF)
set(USE_METAL OFF)
set(USE_VULKAN ON)
set(USE_OPENCL ON)
set(USE_FLASHINFER OFF)
EOF
export PATH=$HOME/.cargo/bin:$PATH
cmake .. -G Ninja || exit 1
nice ninja -j6 || exit 1
ls -la libmlc_llm*.so tvm/libtvm_runtime*.so 2>/dev/null
cd ~/voice
python3 -m venv mlc-venv
mlc-venv/bin/pip install -q --upgrade pip
mlc-venv/bin/pip install -q "apache-tvm-ffi==0.1.16rc4" || mlc-venv/bin/pip install -q --pre apache-tvm-ffi
mlc-venv/bin/pip install -q numpy psutil requests tqdm pydantic fastapi shortuuid prompt_toolkit safetensors sentencepiece tiktoken
echo "phone runtime build done"
