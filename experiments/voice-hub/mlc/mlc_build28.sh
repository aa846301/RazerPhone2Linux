#!/bin/bash
# WSL: convert + cross-compile Qwen3.5 for the phone with the source-built MLC (TVM 0.28, same commits as the phone).
# Env: QUANTS ("q4f16_1 q4f32_1"), DEVICES ("opencl vulkan"), SRC (HF dir), MODEL_TAG, USE_RNN_FIX=1 to load the
# nightly parser workaround (rnn_state_fix.py).
set -u
. "$HOME/mlc/mlc28_env.sh"
SRC=${SRC:-$HOME/models/Qwen3.5-0.8B}
TAG=${MODEL_TAG:-qwen35-0.8b}
QUANTS=${QUANTS:-"q4f16_1 q4f32_1"}
DEVICES=${DEVICES:-"opencl vulkan"}
if [ "${USE_RNN_FIX:-0}" = 1 ]; then CLI="python $HOME/mlc/mlc_cli.py"; else CLI="python -m mlc_llm"; fi
quiet() { grep -vE "arm_aprofile|Cannot parse target features|File \"<unknown>\""; }
for q in $QUANTS; do
  out=$HOME/mlc/m28-$TAG-$q
  mkdir -p "$out"
  if ! ls "$out"/*-cache.json >/dev/null 2>&1; then
    echo "== convert_weight $q"
    $CLI convert_weight "$SRC" --quantization $q --device cpu -o "$out" 2>&1 | quiet | tail -8
  fi
  echo "== gen_config $q"
  $CLI gen_config "$SRC" --quantization $q --conv-template qwen2 \
    --context-window-size 4096 --prefill-chunk-size 256 --max-batch-size 1 -o "$out" 2>&1 | quiet | tail -2
  for d in $DEVICES; do
    echo "== compile $q $d"
    $CLI compile "$out/mlc-chat-config.json" --device $d --host aarch64-linux-gnu \
      -o "$out/lib-$d.tar" 2>&1 | quiet | tail -14
    ls -la "$out/lib-$d.tar" 2>/dev/null
  done
  du -sh "$out"
done
echo "mlc_build28 done"
