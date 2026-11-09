#!/usr/bin/env python3
"""Move the LOAD_W16 macro out of the USE_IMAGE1D_INPUT/MNN_SUPPORT_FP16 conditional in gemv_conv1x1_buf.cl."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
line = ("#define LOAD_W16(idx, base) ((((size_t)(base)) & 15) == 0 ? "
        "as_uchar16(((__global const uint4 *)(base))[(idx)]) : vload16((idx), (base)))\n")
comment = "// RAZER_ALIGNED_W16: aligned 16-byte weight load (see razorphone2linux doc, section 10)\n"
assert s.count(line) == 1, "macro not found exactly once"
s = s.replace(comment + line, "").replace(line, "")
anchor = "__constant sampler_t SAMPLER"
pos = s.index(anchor)
s = s[:pos] + comment + line + "\n" + s[pos:]
open(p, "w", encoding="utf-8").write(s)
print("LOAD_W16 now unconditional")
