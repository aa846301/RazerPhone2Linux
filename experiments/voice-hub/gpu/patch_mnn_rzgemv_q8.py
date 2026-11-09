#!/usr/bin/env python3
"""Extend the razer GEMV hook to 8-bit asymmetric weights (gemv_q8_razer, buffer input)."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "gemv_q8_razer" in s:
    sys.exit("already patched")
old_cond = """        if (rzWanted && mResource->mNumQuantBit == 4 && mInputImage1d != nullptr && inputChannelLeaves == 0 &&
            outChannel % 8 == 0 && blockDim % 4 == 0 && blockDim > 0 && (inputChannelBlocks * 4) % blockDim == 0 &&"""
new_cond = """        const bool rzQ4 = mResource->mNumQuantBit == 4 && mInputImage1d != nullptr;
        const bool rzQ8 = mResource->mNumQuantBit == 8 && inputChannels % 4 == 0;
        if (rzWanted && (rzQ4 || rzQ8) && inputChannelLeaves == 0 &&
            outChannel % 8 == 0 && blockDim % 4 == 0 && blockDim > 0 && (inputChannelBlocks * 4) % blockDim == 0 &&"""
assert s.count(old_cond) == 1
s = s.replace(old_cond, new_cond)
old_k = 'buildKernel("gemv_q4_razer_buf", "gemv_q4_razer", rzOpt,'
assert s.count(old_k) == 1
s = s.replace(old_k, 'buildKernel("gemv_q4_razer_buf", rzQ4 ? "gemv_q4_razer" : "gemv_q8_razer", rzOpt,')
old_in = "                ret |= unit.kernel->get().setArg(idx++, sizeof(cl_mem), &mInputImage1d);\n"
assert s.count(old_in) == 1
s = s.replace(old_in, """                if (rzQ4) {
                    ret |= unit.kernel->get().setArg(idx++, sizeof(cl_mem), &mInputImage1d);
                } else {
                    ret |= unit.kernel->get().setArg(idx++, openCLBuffer(input));
                }
""")
open(p, "w", encoding="utf-8").write(s)
print("q8 hook added")
