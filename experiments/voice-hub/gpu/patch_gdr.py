#!/usr/bin/env python3
"""Append linear_attn_gdr_decode_rz to linear_attention_buf.cl and select it for decode in
LinearAttentionBufExecution.cpp (MNN_RAZER_GDR=0 disables; MNN_RAZER_GDR_RS sets row slices, default 4)."""
import shutil
import sys
cl_path, cpp_path, kernel_path = sys.argv[1:4]
cl = open(cl_path, encoding="utf-8").read()
if "linear_attn_gdr_decode_rz" not in cl:
    shutil.copy(cl_path, cl_path + ".orig")
    cl += open(kernel_path, encoding="utf-8").read()
    open(cl_path, "w", encoding="utf-8").write(cl)
cpp = open(cpp_path, encoding="utf-8").read()
if "linear_attn_gdr_decode_rz" in cpp:
    sys.exit("cpp already patched")
shutil.copy(cpp_path, cpp_path + ".orig")
old_build = """    mKernelGatedDeltaRule = runtime->buildKernel("linear_attention_buf", "linear_attn_gated_delta_rule",
                                                 gateDeltaRuleBuildOptions, mOpenCLBackend->getPrecision());"""
new_build = """    // razorphone2linux: coalesced decode kernel (doc section 12); MNN_RAZER_GDR=0 restores the original
    int rzGdrRS = 0;
    {
        const char *e = getenv("MNN_RAZER_GDR");
        const bool want = !(e != nullptr && e[0] == '0');
        int rs = 4;
        if (const char *r = getenv("MNN_RAZER_GDR_RS")) {
            rs = atoi(r);
        }
        if (want && seqLen == 1 && dv % 4 == 0 && rs > 0 && dk % rs == 0 && (dv / 4) * rs <= 256) {
            rzGdrRS = rs;
        }
    }
    if (rzGdrRS > 0) {
        auto opts = gateDeltaRuleBuildOptions;
        opts.emplace("-DRZ_RS=" + std::to_string(rzGdrRS));
        opts.emplace("-DRZ_CT=" + std::to_string(dv / 4));
        mKernelGatedDeltaRule = runtime->buildKernel("linear_attention_buf", "linear_attn_gdr_decode_rz", opts,
                                                     mOpenCLBackend->getPrecision());
        if (mKernelGatedDeltaRule == nullptr) {
            rzGdrRS = 0;
        }
    }
    if (rzGdrRS == 0) {
        mKernelGatedDeltaRule = runtime->buildKernel("linear_attention_buf", "linear_attn_gated_delta_rule",
                                                     gateDeltaRuleBuildOptions, mOpenCLBackend->getPrecision());
    }"""
assert cpp.count(old_build) == 1
cpp = cpp.replace(old_build, new_build)
old_gws = "        mGWSGatedDeltaRule = {(uint32_t)local_size, (uint32_t)UP_DIV(dv, 4) * H * batch};"
assert cpp.count(old_gws) == 1
cpp = cpp.replace(old_gws, """        if (rzGdrRS > 0) {
            mGWSGatedDeltaRule = {(uint32_t)((dv / 4) * rzGdrRS), (uint32_t)(H * batch)};
        } else {
            mGWSGatedDeltaRule = {(uint32_t)local_size, (uint32_t)UP_DIV(dv, 4) * H * batch};
        }""")
old_lws = "        mLWSGatedDeltaRule = {(uint32_t)local_size, 1};"
assert cpp.count(old_lws) == 1
cpp = cpp.replace(old_lws, """        if (rzGdrRS > 0) {
            mLWSGatedDeltaRule = {(uint32_t)((dv / 4) * rzGdrRS), 1};
        } else {
            mLWSGatedDeltaRule = {(uint32_t)local_size, 1};
        }""")
if "#include <cstdlib>" not in cpp:
    cpp = "#include <cstdlib>\n" + cpp
open(cpp_path, "w", encoding="utf-8").write(cpp)
print("gdr patch applied")
