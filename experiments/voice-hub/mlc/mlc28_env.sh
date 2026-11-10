# Source me (WSL or phone): use the mlc-llm 44fd06d checkout + its TVM 0.28 builds via PYTHONPATH (no pip install).
# MLC28_ROOT: the mlc-llm checkout; MLC28_VENV: python venv with deps (numpy, safetensors, ...).
: "${MLC28_ROOT:=$HOME/mlc28/mlc-llm}"
: "${MLC28_VENV:=$HOME/mlc28/venv}"
_tvm=$MLC28_ROOT/3rdparty/tvm
export PYTHONPATH="$_tvm/python:$_tvm/3rdparty/tvm-tirx/python:$MLC28_ROOT/python${PYTHONPATH:+:$PYTHONPATH}"
if [ -d "$_tvm/build/lib" ]; then
  export TVM_LIBRARY_PATH="$_tvm/build/lib"          # full compiler build (WSL)
else
  export TVM_LIBRARY_PATH="$MLC28_ROOT/build/lib"    # runtime-only build inside mlc-llm (phone)
fi
export MLC_LIBRARY_PATH="$MLC28_ROOT/build"
export LD_LIBRARY_PATH="$TVM_LIBRARY_PATH:$MLC_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$MLC28_VENV/bin:$PATH"
