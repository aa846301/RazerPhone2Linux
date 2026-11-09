#!/usr/bin/env python3
"""Make MNN's 4-bit GEMV read weights with 16-byte aligned loads when possible.

vload16() on a `__global const uchar*` only promises 1-byte alignment, and Mesa's
freedreno/ir3 then splits the access into narrow loads: 8.8 GB/s vs 16.9 GB/s for
the same bytes read as uint4 (measured with cl_vload.c on Adreno 630, Mesa 26.2.6).
For 4-bit weights weight_offset = oc*srcChannelC4*16 and each step is 16 bytes, so the
address is 16-byte aligned whenever the buffer base is; we still check at runtime and
fall back to vload16 so results can never change.
"""
import re
import shutil
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
if "RAZER_ALIGNED_W16" in src:
    sys.exit("already patched")
shutil.copy(path, path + ".orig")
macro = (
    "// RAZER_ALIGNED_W16: aligned 16-byte weight load (see razorphone2linux doc, section 10)\n"
    "#define LOAD_W16(idx, base) ((((size_t)(base)) & 15) == 0 ? "
    "as_uchar16(((__global const uint4 *)(base))[(idx)]) : vload16((idx), (base)))\n"
)
# insert after the leading #ifdef/#pragma block (before the first #define)
pos = src.find("#define")
src = src[:pos] + macro + src[pos:]
pat = re.compile(r"uchar16 charWeightsInt40 = vload16\((\w+), weight \+ weight_offset\);")
src, n = pat.subn(r"uchar16 charWeightsInt40 = LOAD_W16(\1, weight + weight_offset);", src)
open(path, "w", encoding="utf-8").write(src)
print(f"patched {n} weight loads")
