#!/bin/bash
# Phone: smoke test of mnn_nlu_worker prefix reuse with Qwen3-1.7B on the GPU (OpenCL, fp16).
export RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu
cd ~/voice/mnn_nlu
M=${MODEL:-$HOME/voice/models/mnn/Qwen3-1.7B-MNN/config.json}
SYS=$(python3 -c 'print("你是智慧家庭指令解析器。只輸出 JSON，格式 {\"device\":裝置,\"action\":動作}。裝置清單：客廳燈、臥室燈、冷氣、窗簾、電風扇、除濕機。動作清單：開、關、調高、調低。" * 6)')
req() { python3 -c 'import json,sys; print(json.dumps({"messages":[{"role":"system","content":sys.argv[1]},{"role":"user","content":sys.argv[2]}],"max_tokens":40}, ensure_ascii=False))' "$SYS" "$1"; }
{
  req "幫我把客廳的燈打開"
  req "冷氣關掉"
  req "窗簾打開一下"
} | timeout 600 taskset -c 4-7 ./mnn_nlu_worker "$M" '{"backend_type":"opencl","precision":"low","thread_num":4}' 2>/dev/null
