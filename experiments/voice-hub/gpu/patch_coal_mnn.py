#!/usr/bin/env python3
"""Add an RZ_COAL loop order to gemv_q4_razer/gemv_q8_razer and select it in the hook for very wide outputs
(lm_head): MNN_RAZER_GEMV_BIG_OC (default 65536) and MNN_RAZER_GEMV_S_BIG (default 4)."""
import sys
cl_path, cpp_path = sys.argv[1:3]
cl = open(cl_path, encoding="utf-8").read()
if "RZ_BLK0" not in cl:
    macros = """
#ifdef RZ_COAL   // every slice visits every block; slices read consecutive chunks inside a block (coalesced)
#define RZ_BLK0 0
#define RZ_BLKSTEP 1
#define RZ_U0 s
#define RZ_USTEP RZ_S
#else            // slices interleave by quant block; each slice streams whole blocks
#define RZ_BLK0 s
#define RZ_BLKSTEP RZ_S
#define RZ_U0 0
#define RZ_USTEP 1
#endif
"""
    cl = cl.replace("#define RZ_R (RZ_L / RZ_S)\n", "#define RZ_R (RZ_L / RZ_S)\n" + macros, 1)
    n1 = cl.count("for (int blk = s; blk < nblk; blk += RZ_S) {")
    n2 = cl.count("for (int u = 0; u < cpb; u++) {")
    assert n1 == 2 and n2 == 2, (n1, n2)
    cl = cl.replace("for (int blk = s; blk < nblk; blk += RZ_S) {", "for (int blk = RZ_BLK0; blk < nblk; blk += RZ_BLKSTEP) {")
    cl = cl.replace("for (int u = 0; u < cpb; u++) {", "for (int u = RZ_U0; u < cpb; u += RZ_USTEP) {")
    open(cl_path, "w", encoding="utf-8").write(cl)
cpp = open(cpp_path, encoding="utf-8").read()
if "MNN_RAZER_GEMV_BIG_OC" not in cpp:
    old = """            if (rzS < 1 || rzS > 64 || (64 % rzS) != 0) {
                rzS = 8;
            }
            std::set<std::string> rzOpt = buildOption;"""
    new = """            if (rzS < 1 || rzS > 64 || (64 % rzS) != 0) {
                rzS = 8;
            }
            int rzBigOc = 65536;
            if (const char *e = getenv("MNN_RAZER_GEMV_BIG_OC")) {
                rzBigOc = atoi(e);
            }
            const bool rzCoal = outChannel >= rzBigOc;
            if (rzCoal) {
                rzS = 4;
                if (const char *e = getenv("MNN_RAZER_GEMV_S_BIG")) {
                    rzS = atoi(e);
                }
                if (rzS < 1 || rzS > 64 || (64 % rzS) != 0) {
                    rzS = 4;
                }
            }
            std::set<std::string> rzOpt = buildOption;
            if (rzCoal) {
                rzOpt.emplace("-DRZ_COAL");
            }"""
    assert cpp.count(old) == 1
    cpp = cpp.replace(old, new)
    open(cpp_path, "w", encoding="utf-8").write(cpp)
print("coalesced option added")
