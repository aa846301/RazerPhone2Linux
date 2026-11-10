"""Same export_tvm step for a tiny Qwen3 (non-3.5) config: tells whether the segfault is Qwen3.5-specific."""
import json, tempfile
from pathlib import Path
from mlc_llm.model import MODELS
from mlc_llm.quantization import QUANTIZATION

cfg = {
    "architectures": ["Qwen3ForCausalLM"], "model_type": "qwen3", "hidden_size": 256, "intermediate_size": 512,
    "num_attention_heads": 4, "num_key_value_heads": 2, "head_dim": 64, "num_hidden_layers": 2,
    "rms_norm_eps": 1e-6, "rope_theta": 1000000.0, "vocab_size": 1024, "tie_word_embeddings": True,
    "max_position_embeddings": 4096, "hidden_act": "silu", "attention_bias": False,
}
p = Path(tempfile.mkdtemp()) / "config.json"
p.write_text(json.dumps(cfg))
model = MODELS["qwen3"]
c = model.config.from_file(p)
m, _ = model.quantize[QUANTIZATION["q4f16_1"].kind](c, QUANTIZATION["q4f16_1"])
print(">> export_tvm qwen3", flush=True)
_, params, _ = m.export_tvm(spec=m.get_default_spec(), allow_extern=True)
print(">> qwen3 export ok", len(params), flush=True)
