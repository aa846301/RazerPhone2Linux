#!/bin/bash
# WSL (x86_64, no sudo): build the MLC-LLM compiler from the SAME commits as the phone runtime
# (mlc-llm 44fd06d, mlc-ai/relax 629cc65 = TVM 0.28.dev0) so model libs match the phone ABI exactly.
# Installs cmake/ninja via pip, Rust via rustup (user), LLVM from the official llvm-project release tarball.
set -eu
exec > >(tee "$HOME/mlc/pc_build_mlc28.log") 2>&1
W=$HOME/mlc28
mkdir -p "$W"
cd "$W"

# ---- tools ----------------------------------------------------------------------------------------
python3 -m venv --without-pip venv
if [ ! -x venv/bin/pip ]; then
  curl -sSfL https://bootstrap.pypa.io/get-pip.py -o "$W/get-pip.py"
  venv/bin/python "$W/get-pip.py" -q
fi
venv/bin/pip install -q cmake ninja numpy psutil safetensors sentencepiece tiktoken requests tqdm pydantic \
  fastapi shortuuid prompt_toolkit huggingface_hub ml_dtypes typing_extensions cython scikit-build-core setuptools wheel
export PATH="$W/venv/bin:$HOME/.cargo/bin:$PATH"
if ! command -v cargo >/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
  sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain stable >/dev/null
fi
# LLVM from conda-forge (llvmdev: regular object archives; the llvm-project release tarball ships ThinLTO
# bitcode archives that GNU ld cannot link). micromamba installs it in user space, no sudo.
if [ ! -x "$W/conda/bin/llvm-config" ]; then
  rm -rf "$W/llvm"
  if [ ! -x "$W/micromamba" ]; then
    curl -sSfL https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj -C "$W" bin/micromamba
    mv "$W/bin/micromamba" "$W/micromamba" && rmdir "$W/bin"
  fi
  "$W/micromamba" create -y -q -r "$W/mamba-root" -p "$W/conda" -c conda-forge "llvmdev=19.*" zlib zstd libxml2
fi
ln -sfn "$W/conda" "$W/llvm"
# TVM links libtvm_runtime_extra with -fuse-ld=lld; provide ld.lld from the same env.
[ -x "$W/conda/bin/ld.lld" ] || "$W/micromamba" install -y -q -r "$W/mamba-root" -p "$W/conda" -c conda-forge "lld=19.*"
export PATH="$PATH:$W/conda/bin"
"$W/llvm/bin/llvm-config" --version

# ---- sources (same commits as the phone) --------------------------------------------------------------
if [ ! -d mlc-llm ]; then
  git clone https://github.com/mlc-ai/mlc-llm.git
fi
cd mlc-llm
git checkout -q 44fd06d
git submodule update --init --recursive
git -C 3rdparty/tvm log -1 --format='tvm %h %cd'

# ---- TVM compiler (with LLVM) -------------------------------------------------------------------------
mkdir -p 3rdparty/tvm/build
cat > 3rdparty/tvm/build/config.cmake <<EOF
set(CMAKE_BUILD_TYPE RelWithDebInfo)
set(USE_LLVM "$W/llvm/bin/llvm-config --ignore-libllvm --link-static")
set(TVM_TIRX_USE_LLVM "$W/llvm/bin/llvm-config")
set(LLVM_DIR "$W/llvm/lib/cmake/llvm")
set(HIDE_PRIVATE_SYMBOLS ON)
set(USE_CUDA OFF)
set(USE_METAL OFF)
set(USE_VULKAN OFF)
set(USE_OPENCL OFF)
set(USE_CUBLAS OFF)
set(USE_CUTLASS OFF)
set(USE_THRUST OFF)
EOF
(cd 3rdparty/tvm/build && cmake .. -G Ninja -DLLVM_DIR="$W/llvm/lib/cmake/llvm" \
   -DTVM_TIRX_USE_LLVM="$W/llvm/bin/llvm-config" -DCMAKE_PREFIX_PATH="$W/llvm" && ninja -j14)

# ---- mlc-llm C++ (tokenizers etc., needed by the python package import) ---------------------------------
mkdir -p build
cat > build/config.cmake <<EOF
set(TVM_SOURCE_DIR 3rdparty/tvm)
set(CMAKE_BUILD_TYPE RelWithDebInfo)
set(USE_CUDA OFF)
set(USE_VULKAN OFF)
set(USE_OPENCL OFF)
set(USE_METAL OFF)
set(USE_FLASHINFER OFF)
EOF
(cd build && cmake .. -G Ninja && ninja -j14)

# ---- python packages (editable, pointing at these builds) ------------------------------------------------
ffi=$(ls -d 3rdparty/tvm/3rdparty/tvm-ffi 2>/dev/null || true)
[ -n "$ffi" ] && pip install -q -e "$ffi" || pip install -q --pre apache-tvm-ffi
pip install -q -e 3rdparty/tvm/python 2>/dev/null || pip install -q -e 3rdparty/tvm
pip install -q -e python
export TVM_LIBRARY_PATH="$W/mlc-llm/3rdparty/tvm/build"
python -c "import tvm, mlc_llm; print('tvm', tvm.__version__, tvm.__file__); from mlc_llm.model import MODELS; print('qwen3_5' in MODELS)"
echo "pc_build_mlc28 done"
