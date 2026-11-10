#!/bin/bash
# Phone: python packages from the same mlc-llm checkout as the runtime libs (editable installs).
exec > /tmp/mlc-phone-py.log 2>&1
set -x
cd ~/voice/mlc-llm || exit 1
V=~/voice/mlc-venv/bin
$V/pip uninstall -y apache-tvm-ffi 2>/dev/null
ffi=3rdparty/tvm/3rdparty/tvm-ffi
export PATH=$HOME/.cargo/bin:$PATH
$V/pip install -q cython scikit-build-core setuptools wheel ml_dtypes typing_extensions
$V/pip install -q -e "$ffi" || $V/pip install -q --pre apache-tvm-ffi
$V/pip install -q -e 3rdparty/tvm/python 2>/dev/null || $V/pip install -q -e 3rdparty/tvm
$V/pip install -q -e python
export TVM_LIBRARY_PATH=$HOME/voice/mlc-llm/build/tvm
export MLC_LIBRARY_PATH=$HOME/voice/mlc-llm/build
$V/python -c "import tvm, mlc_llm; print('tvm', tvm.__version__); d=tvm.opencl(0); print('opencl exist', d.exist)"
echo "phone python setup done"
