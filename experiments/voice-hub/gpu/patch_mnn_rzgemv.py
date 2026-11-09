#!/usr/bin/env python3
"""Hook gemv_q4_razer into ConvBufLowMemoryExecution::tuneGemvLowMemory (MNN 3.6.2).
Selected only for 4-bit asymmetric weights with image1d input and aligned shapes; MNN_RAZER_GEMV=0 disables,
MNN_RAZER_GEMV_S=<n> overrides the K-slice count (default 8)."""
import shutil
import sys

p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "gemv_q4_razer" in s:
    sys.exit("already patched")
shutil.copy(p, p + ".orig")
anchor = "    int local_size = useLocalMem ? 128 : 1;\n    if (useLocalMem && mOpenCLBackend->getCLTuneLevel() != None"
assert s.count(anchor) == 1, s.count(anchor)
hook = r'''    // razorphone2linux: Adreno 630 / Mesa rusticl tuned GEMV (doc/voice-hub-night-report-2026-11-09.md, section 11)
    {
        const char *rzEnv = getenv("MNN_RAZER_GEMV");
        const bool rzWanted = !(rzEnv != nullptr && rzEnv[0] == '0');
        if (rzWanted && mResource->mNumQuantBit == 4 && mInputImage1d != nullptr && inputChannelLeaves == 0 &&
            outChannel % 8 == 0 && blockDim % 4 == 0 && blockDim > 0 && (inputChannelBlocks * 4) % blockDim == 0 &&
            mResource->mBuildOptions.count("-DASYMMETRIC") > 0) {
            int rzS = 8;
            if (const char *e = getenv("MNN_RAZER_GEMV_S")) {
                rzS = atoi(e);
            }
            if (rzS < 1 || rzS > 64 || (64 % rzS) != 0) {
                rzS = 8;
            }
            std::set<std::string> rzOpt = buildOption;
            rzOpt.emplace("-DRZ_L=64");
            rzOpt.emplace("-DRZ_S=" + std::to_string(rzS));
            auto rzKernel = mOpenCLBackend->getOpenCLRuntime()->buildKernel("gemv_q4_razer_buf", "gemv_q4_razer", rzOpt,
                                                                            mOpenCLBackend->getPrecision());
            if (rzKernel != nullptr) {
                unit.kernel = rzKernel;
                const int groups8 = outChannel / 8;
                const int rzR = 64 / rzS;
                uint32_t idx = 0;
                cl_int ret = CL_SUCCESS;
                if (mResource->mUseImage) {
                    ret |= unit.kernel->get().setArg(idx++, *mResource->mKernelImage.get());
                } else {
                    ret |= unit.kernel->get().setArg(idx++, *mResource->mKernelBuffer.get());
                }
                ret |= unit.kernel->get().setArg(idx++, *mResource->mDequantScaleOffsetBuffer.get());
                ret |= unit.kernel->get().setArg(idx++, openCLBuffer(mResource->mBias.get()));
                ret |= unit.kernel->get().setArg(idx++, sizeof(cl_mem), &mInputImage1d);
                ret |= unit.kernel->get().setArg(idx++, openCLBuffer(output));
                ret |= unit.kernel->get().setArg(idx++, static_cast<int>(inputChannelBlocks));
                ret |= unit.kernel->get().setArg(idx++, static_cast<int>(outputChannelBlocks));
                ret |= unit.kernel->get().setArg(idx++, static_cast<int>(groups8));
                ret |= unit.kernel->get().setArg(idx++, static_cast<int>(blockDim));
                ret |= unit.kernel->get().setArg(idx++, static_cast<float>(1.0f / mResource->mCoef));
                MNN_CHECK_CL_SUCCESS(ret, "setArg gemv_q4_razer");
                if (ret == CL_SUCCESS) {
                    mGlobalWorkSize = {static_cast<uint32_t>(UP_DIV(groups8, rzR) * 64), 1};
                    mLocalWorkSize = {64, 1};
                    mOpenCLBackend->recordKernel2d(unit.kernel, mGlobalWorkSize, mLocalWorkSize);
                    unit.globalWorkSize = {mGlobalWorkSize[0], mGlobalWorkSize[1]};
                    unit.localWorkSize = {mLocalWorkSize[0], mLocalWorkSize[1]};
                    return;
                }
            }
        }
    }
'''
s = s.replace(anchor, hook + anchor)
if "#include <cstdlib>" not in s:
    s = "#include <cstdlib>\n" + s
open(p, "w", encoding="utf-8").write(s)
print("hook inserted")
