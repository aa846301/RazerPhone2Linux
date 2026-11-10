"""Step through MLC convert_weight for Qwen3.5 to find the segfaulting call (prints before each step)."""
import sys
from pathlib import Path


def step(msg):
    print(">>", msg, flush=True)


step("import")
from mlc_llm.model import MODELS
from mlc_llm.quantization import QUANTIZATION

src = Path(sys.argv[1])
model_type = sys.argv[2] if len(sys.argv) > 2 else "qwen3_5"
q = QUANTIZATION["q4f16_1"]
model = MODELS[model_type]
step(f"config.from_file ({model_type})")
cfg = model.config.from_file(src / "config.json")
step(f"config ok: {type(cfg).__name__}")
step("quantize")
m, qmap = model.quantize[q.kind](cfg, q)
step("quantize ok")
step("get_default_spec")
spec = m.get_default_spec()
step("export_tvm")
_, named_params, _ = m.export_tvm(spec=spec, allow_extern=True)
step(f"export ok: {len(named_params)} params")
