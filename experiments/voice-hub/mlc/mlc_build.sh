#!/bin/bash
# WSL (x86_64): convert Qwen3.5-0.8B to MLC format and cross-compile model libs for the phone
# (aarch64 Linux host code + OpenCL / Vulkan device code). Output: ~/mlc/<tag>-<quant>/lib-<dev>.tar (link on phone).
# Uses mlc_cli.py, which loads rnn_state_fix.py (nightly TVMScript parser segfault workaround).
set -u
V=~/mlc-venv/bin
CLI="$V/python $HOME/mlc/mlc_cli.py"
SRC=${SRC:-$HOME/models/Qwen3.5-0.8B}
TAG=${MODEL_TAG:-qwen35-0.8b}
QUANTS=${QUANTS:-"q4f16_1 q4f32_1"}
DEVICES=${DEVICES:-"opencl vulkan"}
quiet() { grep -vE "arm_aprofile|Cannot parse target features|File \"<unknown>\""; }
for q in $QUANTS; do
  out=$HOME/mlc/$TAG-$q
  mkdir -p "$out"
  if ! ls "$out"/*-cache.json >/dev/null 2>&1; then
    echo "== convert_weight $q"
    $CLI convert_weight "$SRC" --quantization $q --device cpu -o "$out" 2>&1 | quiet | tail -6
  fi
  echo "== gen_config $q"
  $CLI gen_config "$SRC" --quantization $q --conv-template qwen2 \
    --context-window-size 4096 --prefill-chunk-size 256 --max-batch-size 1 -o "$out" 2>&1 | quiet | tail -3
  for d in $DEVICES; do
    echo "== compile $q $d"
    $CLI compile "$out/mlc-chat-config.json" --device $d --host aarch64-linux-gnu \
      -o "$out/lib-$d.tar" 2>&1 | quiet | tail -12
    ls -la "$out/lib-$d.tar" 2>/dev/null
  done
  du -sh "$out"
done
echo "mlc_build done"
