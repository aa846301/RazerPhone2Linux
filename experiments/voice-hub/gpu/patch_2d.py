#!/usr/bin/env python3
"""Switch razer GEMV to a 2D split: RZ_SB (quant-block interleave) x RZ_SC (chunks inside a block).
Default SB=8, SC=2 (env MNN_RAZER_GEMV_SB / _SC); wide outputs (lm_head, oc >= MNN_RAZER_GEMV_BIG_OC) default to the same SB=8, SC=2
(measured faster than SB=1, SC=4 once the true read ceiling was found; env MNN_RAZER_GEMV_SB_BIG / _SC_BIG)."""
import sys
cl_path, cpp_path = sys.argv[1:3]
cl = open(cl_path, encoding="utf-8").read()
if "RZ_SB" not in cl:
    old_hdr = cl[cl.index("#ifndef RZ_S\n"):cl.index("__constant sampler_t RZ_SAMPLER")]
    new_hdr = """#ifndef RZ_SB
#define RZ_SB 8
#endif
#ifndef RZ_SC
#define RZ_SC 2
#endif
#define RZ_S (RZ_SB * RZ_SC)
#define RZ_R (RZ_L / RZ_S)

"""
    cl = cl.replace(old_hdr, new_hdr)
    # per-thread coordinates + loops (both kernels)
    cl = cl.replace("const int s = lid % RZ_S, r = lid / RZ_S;",
                    "const int s = lid % RZ_S, r = lid / RZ_S;\n    const int sb = s / RZ_SC, sc = s % RZ_SC;")
    n1 = cl.count("for (int blk = RZ_BLK0; blk < nblk; blk += RZ_BLKSTEP) {")
    n2 = cl.count("for (int u = RZ_U0; u < cpb; u += RZ_USTEP) {")
    assert n1 == 2 and n2 == 2, (n1, n2)
    cl = cl.replace("for (int blk = RZ_BLK0; blk < nblk; blk += RZ_BLKSTEP) {", "for (int blk = sb; blk < nblk; blk += RZ_SB) {")
    cl = cl.replace("for (int u = RZ_U0; u < cpb; u += RZ_USTEP) {", "for (int u = sc; u < cpb; u += RZ_SC) {")
    # tree reduction over the S lanes of a row
    old_red = """    red[lid] = acc;
    barrier(CLK_LOCAL_MEM_FENCE);
    if (s != 0 || g >= groups8) return;
    for (int i = 1; i < RZ_S; i++) acc += red[lid + i];"""
    new_red = """    red[lid] = acc;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int st = RZ_S / 2; st > 0; st >>= 1) {
        if (s < st) red[lid] += red[lid + st];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    if (s != 0 || g >= groups8) return;
    acc = red[lid];"""
    assert cl.count(old_red) == 2, cl.count(old_red)
    cl = cl.replace(old_red, new_red)
    open(cl_path, "w", encoding="utf-8").write(cl)
cpp = open(cpp_path, encoding="utf-8").read()
if "MNN_RAZER_GEMV_SB" not in cpp:
    start = cpp.index("            int rzS = 8;")
    end = cpp.index('            rzOpt.emplace("-DRZ_S=" + std::to_string(rzS));') + len('            rzOpt.emplace("-DRZ_S=" + std::to_string(rzS));')
    new = """            auto rzEnvInt = [](const char *name, int def) {
                const char *e = getenv(name);
                return e != nullptr ? atoi(e) : def;
            };
            const bool rzWide = outChannel >= rzEnvInt("MNN_RAZER_GEMV_BIG_OC", 65536);
            int rzSB = rzWide ? rzEnvInt("MNN_RAZER_GEMV_SB_BIG", 8) : rzEnvInt("MNN_RAZER_GEMV_SB", 8);
            int rzSC = rzWide ? rzEnvInt("MNN_RAZER_GEMV_SC_BIG", 2) : rzEnvInt("MNN_RAZER_GEMV_SC", 2);
            if (rzSB < 1 || rzSC < 1 || rzSB * rzSC > 64 || (64 % (rzSB * rzSC)) != 0) {
                rzSB = rzWide ? 8 : 8;
                rzSC = rzWide ? 2 : 2;
            }
            const int rzS = rzSB * rzSC;
            std::set<std::string> rzOpt = buildOption;
            rzOpt.emplace("-DRZ_L=64");
            rzOpt.emplace("-DRZ_SB=" + std::to_string(rzSB));
            rzOpt.emplace("-DRZ_SC=" + std::to_string(rzSC));"""
    cpp = cpp[:start] + new + cpp[end:]
    open(cpp_path, "w", encoding="utf-8").write(cpp)
print("2d split applied")
