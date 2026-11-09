#!/usr/bin/env python3
"""Add an env-gated trace (MNN_KERNEL_TRACE=1) printing program/kernel/options on first kernel creation."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "MNN_KERNEL_TRACE" in s:
    sys.exit("already patched")
old = """        if (firstCreate) {
            kernel->getWorkGroupInfo(*mFirstGPUDevicePtr, CL_KERNEL_WORK_GROUP_SIZE, &kiter->second.maxWorkGroupSize);"""
new = """        if (firstCreate) {
            if (getenv("MNN_KERNEL_TRACE")) {
                MNN_PRINT("KTRACE %s %s [%s]\\n", programName.c_str(), kernelName.c_str(), buildOptionsStr.c_str());
            }
            kernel->getWorkGroupInfo(*mFirstGPUDevicePtr, CL_KERNEL_WORK_GROUP_SIZE, &kiter->second.maxWorkGroupSize);"""
assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)
if "#include <cstdlib>" not in s:
    s = "#include <cstdlib>\n" + s
open(p, "w", encoding="utf-8").write(s)
print("trace patch applied")
