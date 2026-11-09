# Adreno 630 GPU 推理實驗（MNN + Mesa rusticl）

這個資料夾放的是 2026-11-09 的 GPU 剖析和優化工具。完整的數據和結論在 `doc/voice-hub-night-report-2026-11-09.md` 第八到十一節。

## 環境

- Mesa 26.2.6：由 `mesa_build.sh` 編譯，裝在 `/opt/mesa-26.2.6`。
- mesa-libclc：llvm_21 分支，由 `libclc_build.sh` 編譯，裝在 `/opt/mesa-libclc`。
- 系統原本的 Mesa 不動。要用新版時加上這些環境變數：
  `RUSTICL_ENABLE=freedreno OCL_ICD_VENDORS=/opt/mesa-26.2.6/etc/OpenCL/vendors LD_LIBRARY_PATH=/opt/mesa-26.2.6/lib/aarch64-linux-gnu`
- MNN 3.6.2：在手機上的 `~/voice/mnn/MNN-3.6.2` 編譯，選項是 `MNN_OPENCL`、`MNN_ARM82`、`MNN_BUILD_LLM`、`MNN_LOW_MEMORY`。
- 換過驅動或 kernel 之後，要先刪掉 `build/tmp/mnn_cachefile.bin`。舊的調校快取會造成 `CL ERROR -54`。

## 對 MNN 的修改（只在手機上的原始碼樹，套用腳本放在這裡）

| 檔案 | 內容 |
| --- | --- |
| `gemv_q4_razer_buf.cl` + `patch_mnn_rzgemv.py` | **自寫的 4-bit 非對稱 GEMV**（batch 1），在 `tuneGemvLowMemory` 中接管。可以用 `MNN_RAZER_GEMV=0` 關閉，用 `MNN_RAZER_GEMV_S` 指定 K 切片數（預設 8） |
| `patch_gemv.py` | 讓原版 `gemv_conv_c8_buf` 改用對齊的 16-byte 權重讀取（`LOAD_W16`），執行時會檢查位址是否對齊 |
| `patch_trace.py` | 設 `MNN_KERNEL_TRACE=1` 時，印出每個 kernel 第一次建立時的程式名稱和編譯選項 |

加了新的 `.cl` 檔之後，要在 `source/backend/opencl/execution/cl` 執行 `python3 opencl_codegen.py .`，再**重新跑一次 CMake configure**，因為 CMake 只在 configure 時收集原始檔。

## 量測工具

| 檔案 | 用途 |
| --- | --- |
| `cl_launch.c`、`cl_breakdown.c` | 單一 kernel 每次呼叫的開銷，以及 QUEUED/SUBMIT/START/END 各階段的拆解 |
| `latency_matrix.sh` | 分別切換 CPU 深度睡眠、CPU 調頻、GPU 調頻，看各自對呼叫延遲的影響 |
| `cl_readbw.c`、`cl_vload.c` | 早期的讀取測試（同時發出的讀取不足，量到 14–17 GB/s 偏低）；比較 `vload16(uchar*)` 和對齊讀取 |
| `cl_bwmax.c`、`cpu_bw.c`、`bwmax.sh` | 真正的讀取上限：GPU 24.1 GB/s、CPU 大核 17.9 GB/s（報告第十四節） |
| `gemv_exp.cl`、`gemv_exp_bench.c`、`gemv_exp.sh` | GEMV 瓶頸拆解：只讀、只算、手動展開、半精度、`mad24` 等 12 種模式 |
| `gemv_disasm.sh`、`disstats.sh` | 印出 ir3 機器碼與暫存器、停頓統計（需 `MESA_SHADER_CACHE_DISABLE=true`） |
| `lmhead_ab.sh`、`gp_conv.py` | 實機 A/B lm_head 分工；列出每個 token 的 GEMV 呼叫時間 |
| `alu_tp.cl`、`alu_tp.c`、`alu_tp.sh`、`cl_tmu.c` | 4-bit 解碼的指令成本與紋理單元吞吐量（報告 15.4） |
| `cl_dispatch.c`、`dispatch.sh` | 每個 kernel 的送出、GPU 執行與空檔時間（報告 15.1） |
| `dt_audit.sh`、`boost_ab.sh` | DT／核心設定唯讀檢查；大核 2.8 GHz boost A/B（報告 15.2） |
| `patch_llama_subgroups.py`、`patch_llama_rusticl_defs.py`、`patch_llama_kernels_rusticl.sh`、`llama_cl_build.sh`、`llama_cl_test.sh`、`cl_compile_all.c` | 讓 llama.cpp OpenCL 在 rusticl 上執行，並驗證正確性與速度（報告 15.3） |
| `gemv_bench.c`、`gemv_custom_bench3.c`、`gemv_custom.cl` | 單獨對照 MNN 原版 GEMV 和自寫版本（含正確性比對） |
| `mnn_prof_build.sh`、`gp2.py` | `MNN_GPU_TIME_PROFILE` 編譯，並把每個 token 的 GPU 時間依 kernel 分類加總 |
| `rz_tuned.sh` | 在 CPU 效能模式下測自寫 GEMV 的速度（結束後會還原設定） |

## 結果摘要（Qwen3.5-0.8B，GPU 生成 tok/s）

| 階段 | tg |
| --- | --- |
| 舊 Mesa 25.2.8 + MNN 原版 | 3.1 |
| 新 Mesa 26.2.6 + mesa-libclc | 12.6–13.1 |
| + 自寫 GEMV | 17.9 |
| + 推理期間 CPU 不降頻、不深度睡眠 | **21.4** |
| 對照：MNN CPU | 19.6 |
