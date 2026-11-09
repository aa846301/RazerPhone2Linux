#!/usr/bin/env python3
"""llama.cpp OpenCL kernels detect Adreno through cl_qcom_reqd_sub_group_size (proprietary driver only).
On rusticl that extension is absent, so ADRENO_GPU / REQD_SUBGROUP_SIZE_* stay undefined and kernels fail to
compile. When GGML_OPENCL_RUSTICL_ADRENO=1, append those defines to every clBuildProgram. Pair it with
IR3_SHADER_DEBUG=thread64 so ir3 really uses 64-wide subgroups, which the kernels assume."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "        err = clBuildProgram(p, 0, NULL, compile_opts.c_str(), NULL, NULL);\n        if (err == CL_SUCCESS) {\n            return p;"
new = """        // razer: rusticl lacks cl_qcom_reqd_sub_group_size; define the Adreno macros explicitly
        std::string rz_opts = compile_opts;
        if (getenv("GGML_OPENCL_RUSTICL_ADRENO") && atoi(getenv("GGML_OPENCL_RUSTICL_ADRENO"))) {
            rz_opts += " -DADRENO_GPU=1 -DREQD_SUBGROUP_SIZE_64= -DREQD_SUBGROUP_SIZE_128= "
                       "-DCLK_SUB_GROUP_SHUFFLE_WIDTH_WAVE_SIZE_QCOM=0 "
                       "-Dqcom_sub_group_shuffle_xor(v,m,w,d)=sub_group_shuffle_xor(v,m) "
                       "-Dqcom_wave_pair_mode(x)=unused ";
        }
        err = clBuildProgram(p, 0, NULL, rz_opts.c_str(), NULL, NULL);
        if (err == CL_SUCCESS) {
            return p;"""
if "GGML_OPENCL_RUSTICL_ADRENO" in s and "qcom_sub_group_shuffle_xor(v,m,w,d)" not in s:
    # upgrade an older application of this patch
    i = s.index('rz_opts += " -DADRENO_GPU=1')
    j = s.index("\n", i)
    s = s[:i] + new.split("        if (getenv")[1].split("{\n", 1)[1].split("\n        }")[0].strip() + s[j:]
    open(p, "w", encoding="utf-8").write(s)
elif "GGML_OPENCL_RUSTICL_ADRENO" not in s:
    assert s.count(old) == 1, s.count(old)
    s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)
print("rusticl Adreno defines patch applied")
