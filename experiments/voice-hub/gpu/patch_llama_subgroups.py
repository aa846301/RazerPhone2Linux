#!/usr/bin/env python3
"""llama.cpp OpenCL: accept rusticl devices that expose the OpenCL C 3.0 feature __opencl_c_subgroups
(and the cl_khr_subgroup_* extensions) but withhold the cl_khr_subgroups name for spec reasons
(rusticl comments: it requires CL_DEVICE_SUB_GROUP_INDEPENDENT_FORWARD_PROGRESS)."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = """    if (opencl_c_version.major == 3 && strstr(ext_buffer.data(), "cl_khr_subgroups") == NULL &&
        strstr(ext_buffer.data(), "cl_intel_subgroups") == NULL) {"""
new = """    // razer: rusticl exposes __opencl_c_subgroups + cl_khr_subgroup_* but not the cl_khr_subgroups name
    if (opencl_c_version.major == 3 && strstr(ext_buffer.data(), "cl_khr_subgroups") == NULL &&
        strstr(ext_buffer.data(), "cl_intel_subgroups") == NULL &&
        strstr(ext_buffer.data(), "cl_khr_subgroup_extended_types") == NULL) {"""
if new not in s:
    assert s.count(old) == 1, "pattern not found"
    s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)
print("subgroup gate relaxed")
