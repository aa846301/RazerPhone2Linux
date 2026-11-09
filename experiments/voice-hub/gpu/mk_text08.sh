#!/bin/bash
# Text-only Qwen3.5-0.8B config for llm_demo (no vision tower), CPU and OpenCL variants.
B=$HOME/voice/models/mnn/Qwen3.5-0.8B-MNN
T=$HOME/voice/models/mnn/Qwen3.5-0.8B-text
mkdir -p $T
for f in llm.mnn llm.mnn.json llm.mnn.weight tokenizer.txt; do ln -sf $B/$f $T/$f; done
python3 - "$B" "$T" <<'EOF'
import json, sys
b, t = sys.argv[1] + '/', sys.argv[2] + '/'
lc = json.load(open(b + 'llm_config.json'))
for k in list(lc):
    if 'visual' in k or k in ('mllm', 'vision', 'image_size', 'image_mean', 'image_norm'):
        lc.pop(k)
lc['is_visual'] = False
json.dump(lc, open(t + 'llm_config.json', 'w'), ensure_ascii=False, indent=1)
c = json.load(open(b + 'config.json'))
c.pop('mllm', None)
for be in ('cpu', 'opencl'):
    d = dict(c, backend_type=be, thread_num=4, precision='low', sampler_type='greedy')
    d['jinja'] = {'context': {'enable_thinking': False}}
    json.dump(d, open(t + f'config-{be}.json', 'w'), ensure_ascii=False, indent=1)
print('keys removed ok')
EOF
cd ~/voice/mnn/MNN-3.6.2/build
for be in cpu opencl; do
  echo "===== $be"
  env RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu \
    timeout 900 stdbuf -o0 ./llm_demo $T/config-$be.json /tmp/prompts.txt 80 > /tmp/demo08t-$be.txt 2>&1
  grep -vE 'Rusticl|CPU Group|device supports|ache|^\s*$|config path|tuning|main, 3|vision|pixels|audio|sample time|^#|prompt file|tokens num|prefill time|decode time' /tmp/demo08t-$be.txt | head -n 20
done
