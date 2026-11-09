# 語音中樞夜間報告（2026-11-08 23:00 – 2026-11-09 02:00）

整夜**沒有播放任何聲音**：沒有執行 aplay 或 speaker-test，TTS 只產生檔案。
狀態標籤沿用規劃書第七節：候選方案／文件已確認／環境已確認／實機已驗證／整合已驗證／可靠步驟。

## 一、結果總表

| 模組 | 方案 | 狀態 | 量測數據（實測，不是預估） |
| --- | --- | --- | --- |
| 麥克風 | WCD9340 DMIC1（主）、DMIC3（雙聲道），+12 dB | **實機已驗證** | 修 DTS 前全是 0；修正後底噪 −58 dBFS（+12 dB），使用者確認錄得到鍵盤聲；可直接以 16 kHz 錄音；雙聲道可用 |
| 關機 | `razer-modem-stop` 只停 MSS | **實機已驗證** | 原本關機卡 15 分鐘以上（SLIMbus／clk 死結），修正後重開機約 30 秒 |
| 喚醒詞 | sherpa-onnx KWS zipformer-wenetspeech-3.3M，關鍵詞「嘿賈伯斯」= `h ēi j iǎ b ó s ī` | **實機已驗證（合成語音）** | 不需訓練；Windows 臺灣語音 Hanhan 的 9 段正向樣本全部偵測到；2.5 分鐘負向語音 0 次誤喚醒；單執行緒 RTF 約 0.20（同時在編譯，是悲觀值） |
| ASR | SenseVoice Small int8（sherpa-onnx 2.0.1） | **實機已驗證（合成語音）** | 46 句臺灣語音合成指令，數字經 ITN 輸出（26度、30%、24）；需要加 OpenCC s2twp；殘餘錯誤：燈條→燈調、調亮→掉亮、設→攝、欸→被。RTF 0.43 是在 cpufreq 失效又同時編譯下量的，**不能代表正常速度** |
| NLU | Qwen3-0.6B Q4_K_M + llama.cpp（JSON schema 約束）+ `validate()` | **環境已確認，準確率不足** | 前 25 句只有 9 句正確（36%），每句 14–93 秒。問題：溫度輸出成 49、52 這類亂數；「百分之三十」變成 70；多指令會漏掉動作；幾乎每句都附上不必要的 clarify。速度數字在 cpufreq 失效下量測，**無效** |
| 驗證器 | `nlu.py validate()` | **環境已確認** | 用標準答案跑 46/46 全對；能擋下不存在的設備、未授權設備、超出範圍的溫度 |
| VAD | Silero VAD | 候選方案 | 模型已下載到手機，尚未測試 |
| TTS | Kokoro／Piper／Matcha | 候選方案 | 下載太慢（GitHub 約 100–270 KB/s），今晚沒有測 |
| HA | REST／Assist | 候選方案 | 沒有 token，目前用模擬設備清單 `home.json` |

## 二、新發現的問題（依嚴重度排序）

1. **`qcom-cpufreq-hw` 在這次開機註冊失敗**（`CPUFreq HW driver failed to register`，4.85 秒），
   `/sys/devices/system/cpu/cpufreq/` 是空的，CPU 停在 bootloader 留下的頻率，LLM 只有 4.4 token/s。
   今晚第一次盤點時（舊 DTB）cpufreq 是正常的，cpu4 最高 2.65 GHz。新舊 DTB **只差 `/sound audio-routing`**，
   所以比較可能是開機順序造成的偶發問題（log 裡有 `debugfs: 'cpu4' already exists in 'opp'`），**尚未確認**。
   下一步：重開機幾次，看是否每次都會發生，再對照 `fw_devlink=permissive` 和 opp table。**在修好之前，所有效能數據都無效。**
2. Qwen3-0.6B 在目前的提示詞下，**數值和多指令的處理都不可靠**。依原規劃比較的方向，下一輪要做：
   (a) 簡單指令改走規則或 HA Assist，LLM 只處理複雜句；(b) 換用 Qwen3.5-0.8B、Qwen2.5-0.5B、Qwen3-1.7B 比較
   （三個模型都已下載到 `output/models/`，前兩個已傳到手機）；(c) 數值改由程式抽取，不交給模型。
3. ASR 輸出是簡體字，必須接 OpenCC `s2twp`。已加入 `speech_bench.py`，正式管線也需要。

## 三、我修改了哪些原本的作法（如實列出）

| 原規劃 | 實際作法 | 原因 | 最終效果會不會受影響 |
| --- | --- | --- | --- |
| 自訂中文喚醒詞，候選有多個框架 | 先採用 sherpa-onnx 開放詞彙 KWS，不重新訓練 | 文件確認支援拼音 token，實測可以偵測 | 不影響；仍需要真人和遠場的誤喚醒測試，結果不好再訓練 |
| 階段 1 用現成 WAV 測 ASR | 用 Windows 臺灣語音 Hanhan 合成 46 句 | 夜間無法錄真人，Hanhan 是臺灣口音 | **會高估準確率**，最終仍要真人錄音 |
| SenseVoice 完整模型包 | 只用 int8 模型（從 Hugging Face 下載） | 完整包 1 GB，GitHub 下載太慢 | 不影響，原規劃本來就選 int8 |
| ASR 直接輸出臺灣中文 | ASR 後面加 OpenCC 簡轉繁（`s2twp`） | SenseVoice 只輸出簡體 | 不影響，多約 1 ms 延遲 |
| 刷機 | 低風險的 DTB 修改直接寫入 `boot_a`，PC 留有備份；不使用 A/B 和 kexec | `_b` 韌體和 `_a` 不同；kexec 遇到 RPMh 和 ADSP 問題 | 不影響功能；kernel 修改仍需要使用者在場 |
| 關機時停止所有 remoteproc | 只停 MSS | 停 ADSP 會讓 kernel 死結 | 不影響；kernel 正式修正待做 |
| 麥克風路由 | 照原廠 `mixer_paths_tavil.xml`：DMIC1 為主，+12 dB | 原廠設定就是這樣 | 不影響 |

規劃本身的目標**不需要修改**；目前沒有發現做不到的需求。最大的未知數仍然是喇叭（TFA9912 時脈）。

## 四、檔案

- 程式：`experiments/voice-hub/`（README 有說明），`rootfs-scripts/razer-mic-setup.sh`
- 手機上：`~/voice/`（venv、models、bench、llama.cpp），`~/voice/thermal.log`（整夜 CPU 最高 63.7 °C）
- PC 上：`output/models/`（模型），`output/audio-tests/`（合成語音），`output/backup/boot_a-2026-11-08.img`
- 所有修改都**尚未 commit**。

## 五、上午追加（2026-11-09 10:00–）

### 5.1 cpufreq 註冊失敗：原因已找到（**環境已確認**，修正**尚未實機驗證**）

- 從 journal 看，8 次開機中留有 kernel log 的 4 次裡，2 次正常、2 次失敗，屬於**偶發**問題。
- 原因：`qcom-cpufreq-hw` 是內建的（`=y`），但它在 DT 裡的中斷 `interrupts-extended = <&lmh_cluster0 0>, <&lmh_cluster1 0>`
  是由 LMh 驅動提供的，而 LMh 是 module（`CONFIG_QCOM_LMH=m`），要等 rootfs 起來後才會載入。
- 如果 cpufreq 先 probe，每顆 CPU 的 `init` 都會從 `platform_get_irq_optional()` 拿到 -EPROBE_DEFER，而且失敗時只印 `pr_debug`，log 看不到原因。
  所有 policy 都失敗後，`cpufreq_register_driver()` 回傳 -ENODEV，**整次開機都不會再重試**。
- log 裡 `debugfs: 'cpuN' already exists in 'opp'` 這組訊息正好對應「每顆 CPU 各試了一次」。
- 實驗：在執行中重新 bind 驅動，結果**讓 kernel 卡死**。
  - 前一次失敗留下的 OPP table 還握著已經釋放的時脈物件，`clk_set_rate` 在持有 `prepare_lock` 的狀態下無限迴圈，連帶 UFS I/O 也卡住。
  - 只好用 sysrq 重開。**這個方法不能用。**
- 修正：在 `dts/sdm845-razer-aura.dts` 對 `&cpufreq_hw` 加上 `/delete-property/ interrupts-extended;`。
  - 已用 WSL 編譯通過，產物是 `output/sdm845-razer-aura-nolmhirq.dtb`，屬性確實已移除。
  - 代價：kernel 收不到 LMh 的限頻通知（排程器的 thermal pressure），但 OSM/LMh 硬體仍然會自行限頻保護。
  - 根本修正要改 kernel，二選一：把 LMh 編成 `=y`，或讓 cpufreq-hw 在 probe 階段就回傳 -EPROBE_DEFER。
- **意外**：sysrq 重開後，手機一直沒有回到 Wi-Fi（超過 1 小時），需要使用者到現場確認。DTB 修正還沒刷入。

### 5.2 NLU 方案比較（**環境已確認**，在 PC 上用同樣的 GGUF 測準確率；手機速度待 cpufreq 修好後再量）

查到的候選方案：

- HA 內建的 hassil 規則比對：官方有 zh-TW 句型。
- 規則優先、LLM 補位的混合式：這是 HA 官方「優先在本機處理」的作法。
- 針對智慧家庭微調的小模型：Home-FunctionGemma-270M、M5Stack Qwen2.5-HA-0.5B、Home-Phi（3.8B）。這三個主要以英文訓練，或是太大，**本次沒有測**。
- 通用小模型：LFM2.5-1.2B、Gemma-3-1B。

測試集是 `tests.jsonl`（46 句）加上**新增的** `tests-holdout.jsonl`（34 句），共 80 句。

| 方案 | 準確率 | PC 延遲中位數 | 備註 |
| --- | --- | --- | --- |
| hassil + HA 官方 zh-TW 句型 | 26/80（32.5%） | <10 ms | 不支援多指令、相對調整、反問；同音字也無法處理 |
| Qwen2.5-0.5B（原提示／嚴格版） | 27.5% / 35.0% | 1.2 / 0.35 s | |
| Qwen3-0.6B（原提示／嚴格版） | 51.2% / 47.5% | 1.5 / 0.63 s | |
| Gemma-3-1B（原提示／嚴格版） | 17.5% / 43.8% | 6.4 / 0.9 s | |
| LFM2.5-1.2B（原提示／嚴格版） | 20.0% / 60.0% | 3.4 / 2.1 s | |
| Qwen3.5-0.8B（原提示／嚴格版） | 65.0% / 63.7% | 2.3 / 0.7 s | 參數最少的組合裡最準 |
| Qwen3-1.7B（原提示／嚴格版） | 70.0% / 67.5% | 2.5 / 1.4 s | 單獨使用 LLM 時最準 |
| **規則解析器 `nlu_rules.py`** | **80/80（100%）** | **<1 ms** | 見下方限制 |
| 混合式（規則→LLM） | 80/80 | <1 ms | 這 80 句規則全部都有把握，實際上沒有走到 LLM |

「嚴格版」指三件事：entity_id 用 grammar 限定在清單內、加 few-shot 範例、數字由程式先抽出來提示給模型。它對 LFM 和 Gemma 有明顯幫助，對 Qwen 沒有。

**結論和限制（如實列出）：**

- 純 LLM 在 2B 以下最高只有 70%，不能直接用來執行家電指令。
- 規則解析器的 100% **一定高估了**：保留測試句雖然是在寫規則之前寫的，但兩者都出自我。真正的盲測要用**使用者自己說的句子**和真實的 ASR 輸出。
- 建議架構：
  - 規則解析器處理大部分指令，不確定時走反問；
  - 規則判斷為低把握的句子，才交給 Qwen3.5-0.8B 或 Qwen3-1.7B；
  - 所有結果一律經過 `validate()`。
- 規則解析器的設計：
  - 目標不明確時一律反問；只有「關閉整類設備」可以直接執行，因為關閉是安全方向。
  - 只要有任何一個子句需要反問，整句都不執行。
  - 同音錯字用無聲調拼音比對設備清單來修正（客聽、床投燈、臥式、主等）。

### 5.4 開機後沒有 WLAN：自我修復已上線（**實機已驗證**：斷網演練、連續 4 次重開）

- 那次沒有 WLAN 的開機，**在任何地方都沒留下 log**：journal 裡沒有那次開機，ramoops 讀到的是 `error in header`。所以根本原因無法確認。
  比較可能的情況是：那次開機又遇到 I/O 卡住，或是 sysrq-b 硬重開後 modem 沒有正常初始化。
- 實測發現：連正常重開，ramoops 的內容也不會保留，大概是 bootloader 會清掉那塊記憶體。**這台手機不能依賴 ramoops。**
- 新增 `razer-net-watchdog`（`rootfs-scripts/`，已裝在手機並啟用），處理順序：
  1. 斷線 120 秒：nmcli 重新連線；
  2. 斷線 300 秒：重新載入 ath10k；
  3. 斷線 480 秒：正常重開機；
  4. 斷線 720 秒：sysrq-b。

  主迴圈只用 bash 內建指令和 sysfs，所以磁碟 I/O 卡住時仍然能運作。連續重開最多 3 次，避免開機迴圈。
  可以用 `/etc/razerphone2linux/no-net-watchdog` 或 kernel 參數 `razer.netwd=0` 關閉。
- journald 改成 `SyncIntervalSec=15s`：之後就算 I/O 卡住，卡住之前的 log 也比較容易保存下來。
- 演練：故意關掉 Wi-Fi，watchdog 在 120 秒時重連，150 秒後手機重新可以連線。
- cpufreq 修正已刷入 `boot_a`（`boot-cpufix-2026-11-09.img`，sha256 `cc8e48bf…`，PC 有備份）。
  這版只比 `boot-dmic` 少了一個 DT 屬性；kernel 和 ramdisk 都經過 cmp 比對，完全相同。
  **連續 4 次正常重開，cpufreq 每次都註冊成功，Wi-Fi 在 36–41 秒內恢復。**

## 六、SKILL 與「LLM 填固定選項 + 規則」比較（2026-11-09 中午）

**新測試集 `tests-web.jsonl`（40 句）**

- 網路上沒找到現成的繁中智慧家庭指令資料集：SMP-ECDT 是通用對話，MAC-SLU 是車用。
- 改依智慧音箱文件的說法（「燈亮一點／暗一點」、窗簾開合比例、一句多指令、依房間推論），再加上臺灣口語，寫成 40 句。
  內容包含：間接說法、改口、排除、不支援的功能（排程、查詢、色溫、除濕模式）、不在清單上的區域名稱。
- 這 40 句是**在改任何解析器之前**寫好的。

**新增指標 `wrong_executed`**

- 意思是「執行了使用者沒要求的動作」，這是最危險的錯誤類型，比準確率更重要。

**比較的作法**

| 名稱 | 內容 |
| --- | --- |
| 短 SKILL `llm-skill` | 只放相關領域的設備和說明卡，加上自動產生的範例庫（186 句）中最相似的 6 句當範例 |
| 長 SKILL `llm-skill-long` | 放全部設備和狀態、全部說明卡、9 條詳細規則，加上 12 句範例 |
| 固定選項 `slots` | LLM 不寫 entity_id，只從固定選項中挑：device、room、action（12 種）、scope、exclude；再由程式對應到設備，數字也由程式抽取 |
| 規則→固定選項 `rules+slots` | 規則有把握就直接執行，沒把握才交給 `slots` |
| 交叉比對 `agree` | 規則和 `slots` 兩邊都跑，結果一致才執行，不一致就反問 |

**結果**（PC，121 句；`tests-web` 欄是公平的比較）

| 作法 | 模型 | 全部 121 句 | tests-web | 執行錯誤動作（全部／web） |
| --- | --- | --- | --- | --- |
| 規則解析器 | – | 90.9% | 29/40 | 2 / 2 |
| hassil（HA 官方） | – | 28.1% | 11/40 | 0 / 0 |
| 原嚴格提示 | Qwen3-1.7B | 62.8% | 22/40 | 19 / 7 |
| **短 SKILL** | Qwen3-1.7B | **83.5%** | 29/40 | 11 / 5 |
| 長 SKILL | Qwen3-1.7B | 79.3% | 25/40 | 14 / 6 |
| 固定選項 | Qwen3-1.7B | 76.9% | 29/40 | 21 / 8 |
| **規則→固定選項** | Qwen3-1.7B | **95.0%** | **34/40** | **3 / 3** |
| 交叉比對 | Qwen3-1.7B | 85.1% | 30/40 | **1 / 1** |
| 短 SKILL | Qwen3.5-0.8B | 72.7% | 24/40 | 25 / 11 |
| 長 SKILL | Qwen3.5-0.8B | 76.9% | 30/40 | 24 / 8 |
| 規則→固定選項 | Qwen3.5-0.8B | 91.7% | 30/40 | 7 / 7 |
| 短 SKILL | Qwen3-0.6B | 71.1% | 22/40 | 31 / 16 |
| 固定選項 | Qwen3-0.6B | 71.1% | 23/40 | 26 / 14 |
| 短 SKILL | LFM2.5-1.2B | 51.2% | 21/40 | 32 / 11 |

**結論**

- 只靠 LLM，不論用哪種 SKILL，每 121 句都會執行 11–32 次錯誤動作，**不能單獨使用**。
- 短 SKILL 比長 SKILL 好。對 1.7B 模型來說，提示詞愈長愈混亂；0.8B 剛好相反，但差距不大。
- 你提出的「LLM 只填固定選項 + 規則」，單獨使用時會產生較多錯誤動作。
  但**和規則搭配**（規則→固定選項）是所有組合中**最好的**：121 句裡只有 18 句需要用到 LLM。
- 交叉比對最安全（錯誤動作只有 1 次），代價是更常反問。

**調整後 v3（看過 tests-web 才改的，所以這組數字已經不算盲測）**

- 規則遇到排程、改口、查詢這類關鍵詞時，改成交給 LLM 處理。
- 結果：Qwen3-1.7B 全部 **96.7%**，web **36/40**，錯誤動作 **1**；Qwen3.5-0.8B 全部 92.6%，web 31/40，錯誤動作 6。
- 另外試過「規則判斷要反問時也交給 LLM」：錯誤動作從 3 次增加到 11 次，所以**已經撤回**。
- v3 剩下的錯誤：
  - 302「房間好熱」：冷氣是關的，卻只調了溫度，沒有開機；
  - 317、328、334：規則判斷要反問，但其實答案是確定的（例如「廚房跟客廳」「臥房」）。

**手機實測速度**（cpufreq 正常，4 顆大核，`slots`，tests-web）

| 模型 | 延遲中位數 | p90 |
| --- | --- | --- |
| Qwen3.5-0.8B | 4.3 s | 17.9 s |
| Qwen3-1.7B | 11.1 s | 20.0 s |

- 連續負載下溫度最高到 **97 °C**，所以測到一半就停了。
- 實際使用時只有約 15% 的句子會用到 LLM，其餘由規則在 1 ms 內處理完。但用到 LLM 的那 15% 仍然太慢。
- 下一步：把選項改成短代碼，減少輸出的 token 數；或改用 PC GPU／手機 GPU。**尚未實測。**

## 七、溫控、GPU、加速（2026-11-09 下午）

### 7.1 溫控（**實機已驗證**）

- **原因**：mainline `sdm845.dtsi` 的 `cpuN-thermal` 有 90／95 °C 的 passive trip，但**沒有 cooling-maps**。
  CPU 降頻完全交給 LMh 硬體處理，而 LMh 到 95 °C 才會出手，所以先前連續負載時一路升到 97 °C。
- **修正**：每個 CPU zone 新增 80 °C 和 88 °C 兩個 passive trip，綁到該叢集的 cpufreq cooling device，由 step_wise 逐步降頻。
  - 產生方式：`tools/dts-add-cpu-cooling.py` 直接編輯 `boot_a` 現用 DTB 的反編譯文字，所以只新增節點，其他內容完全沒動。
  - 刷入 `boot-thermal-2026-11-09.img`（sha256 `9ac02207…`，PC 有備份）。
  - repo 的 DTS 也加了同樣的節點，已用 WSL 編譯驗證。
- **4 分鐘滿載測試**：
  - 大核自動降到 1.5–2.1 GHz，溫度維持在 80–91 °C（改之前一路升到 97 °C）；
  - 停止負載 30 秒後降回 45 °C；
  - 後續實際使用的語音解析測試中，最高溫度只有 71.7 °C。

### 7.2 Adreno 630 GPU（**GPU 已啟用；llama.cpp 用不了**）

- **現況**：GPU 節點早就是 okay，`/dev/dri/renderD128` 也存在，但 rootfs 裡沒有 `a630_sqe.fw`，所以 GPU 從來沒有真正初始化。
- **補韌體**：
  - `a630_sqe.fw`、`a630_gmu.bin` 來自 linux-firmware（GitLab mirror）。gmu 和 vendor 版本 byte-identical；sqe 用比較新的 linux-firmware 版本。
  - `a630_zap.*` 來自 `vendor_a`，以唯讀方式掛載後複製。
  - 驅動在第一次開啟 GPU 時會重試載入韌體，所以**不需要重開機**。
- Mesa 25.2.8 已安裝，Vulkan 可以偵測到 `Turnip Adreno (TM) 630`，OpenCL（rusticl）可以偵測到 `FD630`（OpenCL 3.0、fp16）。
- **llama.cpp Vulkan**：無法使用。必要的 `storageBuffer16BitAccess` 在 Turnip 的 A630 上是 false，載入模型時直接回報 `Unsupported device`。
- **llama.cpp OpenCL**：
  - 先做了本機實驗性 patch，讓 `FD630` 被認成 Adreno（沒有上游）。
  - 但 rusticl 在 freedreno 上沒有 subgroups，裝置會被丟棄（`drop unsupported device`），實際跑的還是 CPU。
- **結論**：以目前的 Mesa 驅動，A630 無法加速 llama.cpp。其他可能的路線（ncnn、MLC/TVM）是**候選方案，未測**。
- **注意**：GPU 韌體只裝在 rootfs，沒有放進 `boot.img` 的 ramdisk。開機時 GPU 不會初始化，要等第一次被開啟時才會初始化。

### 7.3 CPU 加速

- `/proc/cpuinfo` 沒有 `asimddp`：這顆 CPU 不支援 int8 dot product，所以 Q4_0 的加速路徑用不上。
  實測 Q4_0 反而稍慢：1.7B 生成 6.4 tok/s（Q4_K_M 是 7.1）；0.8B 生成 12.6 tok/s（Q4_K_M 是 13.2）。
- 手機上讀提示詞（pp）很慢：1.7B 約 10.7 tok/s、0.8B 約 28 tok/s。
  固定選項的提示詞是固定的，可以快取，但**服務啟動後的第一次呼叫**要預讀約 950 個 token：0.8B 約 34 秒、1.7B 約 97 秒。正式服務要在啟動時先暖機。
- **縮短輸出**（`slots-c`：單字母鍵，省略預設欄位）：
  - 生成時間：1.7B −40%、0.8B −21%。
  - 準確率：0.8B 略升（規則→固定選項 92.6% → 94.2%）；1.7B 略降（96.7% → 93.4%）。

### 7.4 手機實測：規則→固定選項（縮短版），121 句

| 模型 | 準確率 | tests-web | 執行錯誤動作 | 用到 LLM 的句子 | 這些句子的延遲 |
| --- | --- | --- | --- | --- | --- |
| Qwen3.5-0.8B | 93.4% | 32/40 | 5 | 18/121 | 中位數 **2.9 s**，p90 3.3 s |
| Qwen3-1.7B | 94.2% | 34/40 | 4 | 18/121 | 中位數 5.5 s，p90 9.2 s |

- 不需要 LLM 的 103 句，延遲都在 10 ms 以內。
- 第一次呼叫的預讀時間不算在上表裡。
- 整段測試的最高溫度是 71.7 °C。

## 八、MNN 推理框架（2026-11-09 晚上，**實機已驗證**：速度；整合尚未做）

- MNN 3.6.2（alibaba/MNN，Apache-2.0）。官方沒有 Linux ARM 的 GPU 版編譯檔，所以在手機上以一般使用者身分自行編譯，開啟 ARM82 FP16、OpenCL、Vulkan。
- 模型使用 Hugging Face `taobao-mnn` 官方轉好的 Qwen3.5-0.8B-MNN 和 Qwen3-1.7B-MNN。
- 條件：4 顆大核，low precision，`llm_bench` 跑 pp256 和 tg32。

| 模型 | 框架／後端 | 讀提示詞 pp（tok/s） | 生成 tg（tok/s） |
| --- | --- | --- | --- |
| Qwen3.5-0.8B | llama.cpp CPU（Q4_K_M） | 27.9 | 13.2 |
| Qwen3.5-0.8B | **MNN CPU** | **59.1**（2.1 倍） | **19.6**（1.5 倍） |
| Qwen3.5-0.8B | MNN OpenCL（GPU，rusticl） | 65.6 | 3.1 |
| Qwen3.5-0.8B | MNN Vulkan（GPU，Turnip） | 27.2 | 0.35 |
| Qwen3-1.7B | llama.cpp CPU（Q4_K_M） | 10.7 | 7.1 |
| Qwen3-1.7B | **MNN CPU** | **24.2**（2.3 倍） | **9.0**（1.3 倍） |
| Qwen3-1.7B | **MNN OpenCL（GPU）** | **47.1**（4.4 倍） | 2.1 |
| Qwen3-1.7B | MNN Vulkan | 沒有輸出結果（失敗） | – |

- **GPU 確實能用**：MNN 的 OpenCL 不需要 subgroups，所以可以跑在 Mesa rusticl 上。
  - 讀提示詞時比 CPU 快，1.7B 快將近 2 倍；
  - 但逐字生成慢很多。
- **生成慢不是時脈造成的**：把 GPU 固定在最高 710 MHz 後重測，生成只從 3.1 升到 3.6 tok/s，讀提示詞沒有變化。
  所以瓶頸比較可能在每次 kernel 呼叫的固定開銷（rusticl／驅動），**尚未確認**。
- 測試期間溫度最高 57 °C。
- **GPU 生成慢的原因：已量測確認**
  - MNN `--profile`：Qwen3.5-0.8B 每生成 1 個 token，GPU 要執行約 **1,000 個運算**。
    最簡單的逐元素運算（BinaryOp、UnaryOp、Cast）每個也要 **0.48–0.51 ms**（profile 模式會在每個運算後同步）。
  - 自寫小程式 `cl_launch.c` 量 rusticl：一個只處理 1024 個 float 的 kernel，
    - 每次呼叫後同步：每次 **370–455 µs**；
    - 連續送出、最後才同步：每次 **122–127 µs**，其中 CPU 送出就花 44–51 µs；
    - GPU 讀寫 64 MiB 的實際頻寬是 **21 GB/s**，頻寬是夠的。
  - 生成期間：rusticl 執行緒只用到約 40% CPU，大核大多閒置；GPU 的調頻器一直停在最低 257 MHz，代表 GPU 大部分時間也在閒置。
  - **結論**：瓶頸是 rusticl/freedreno 每次 kernel 呼叫的固定延遲。
    - 實測 3.1 tok/s，等於每個 token 322 ms，平均每個運算約 320 µs；
    - 如果只受頻寬限制，理論上可以到約 45 tok/s。
    - 不是時脈、不是頻寬，也不是 CPU 忙不過來。
  - **能改善的方向（候選方案）**：
    1. 換新版 Mesa：Phoronix 報導 Mesa 26.2 有改善 rusticl 的硬體使用率；
    2. 減少每個 token 的運算數，也就是融合更多運算；
    3. 減少 MNN 裡的同步點；
    4. 混合使用：GPU 讀提示詞、CPU 生成。
- **對語音中樞的意義**：
  - **MNN CPU 全面勝過 llama.cpp CPU**。
  - 暖機時要預讀的約 950 個 token：
    - 0.8B 用 MNN CPU 預估約 16 秒（原本 34 秒）；
    - 1.7B 用 MNN GPU 預估約 20 秒（原本 97 秒）。
- **尚未解決**：MNN 不像 llama.cpp 那樣支援 JSON schema 文法約束輸出。
  要改成「先輸出、再由驗證器檢查選項，不合格就反問」，並重新量測準確率。

## 九、GPU 效能熱點剖析與新版 Mesa（2026-11-09 晚上）

### 9.1 分層剖析舊驅動（Mesa 25.2.8，**實機已驗證**）

- **單一極小 kernel 的時間拆解**（`cl_breakdown.c`，用 OpenCL event profiling）：
  - GPU 實際執行 3.5 µs；
  - CPU enqueue 45 µs、rusticl 佇列 50 µs、SUBMIT→START 151 µs；
  - 加上完成後的通知，同步一次總共 548 µs。
- **每次 kernel 呼叫進 kernel 的次數**（strace 計數）：約 1.65 次 ioctl，大多是 GEM_SUBMIT。
- **perf**：全系統的 CPU 熱點都只有幾個百分比，代表時間主要花在等待，不是在計算。
- **控制變因實驗**：
  - CPU 固定最高頻：連續送出時每次呼叫 130 → 27.5 µs，enqueue 50 → 9 µs；
  - 關閉深度睡眠：有幫助，喚醒延遲 885 µs 是次要因素；
  - GPU 調頻：幾乎沒有影響。
  - 結論：GPU 忙碌時 CPU 大多閒置，schedutil 就把 CPU 降頻，驅動程式碼跟著變慢。
- **MNN 生成一個 token**（0.8B）：
  - 送出 94 次、等 fence 85 次，也就是幾乎每次送出都要等 GPU 做完；
  - 每次等 fence 的中位數約 1.9 ms（在 strace 之下量測）。

### 9.2 新版 Mesa 26.2.6

- 裝在 `/opt/mesa-26.2.6`，並另外編譯 mesa-libclc（llvm_21 分支）到 `/opt/mesa-libclc`。系統的 Mesa 沒有更動。
- **中途出錯**：安裝依賴時，apt 把系統的 `mesa-opencl-icd` 移除了（libclc-18 和 libclc-20 衝突）。已裝回、驗證正常，新版也改用 LLVM 20 重新編譯。
- **沒有 mesa-libclc 時**：MNN 部分 kernel 編譯失敗，訊息是 `nir_shader not fully linked`，接著 MNN 在 `getMaxWorkGroupSize()` 用到空的 kernel 而崩潰。補上 mesa-libclc 後就正常了。
- **MNN 調校快取要刪掉**：舊驅動留下的 `build/tmp/mnn_cachefile.bin` 會造成 `CL ERROR -54`，有 kernel 沒有執行。刪掉快取後就不再出現。
- **新版仍然沒有的功能**：subgroups 還是沒有，所以 llama.cpp OpenCL 仍然不能用；Vulkan 的 storageBuffer16BitAccess 仍是 false，這是 a630 硬體本身的限制。
- **每次呼叫的開銷**（預設電源設定）：
  - 連續送出 138.5 → 25.7 µs；
  - enqueue 48.6 → 7.1 µs；
  - 同步一次 605 → 321 µs。

### 9.3 MNN 最終速度（暖機後量測，4 顆大核，tok/s）

| 模型 | 後端 | pp256 | tg32 |
| --- | --- | --- | --- |
| Qwen3.5-0.8B | llama.cpp CPU（原方案） | 27.9 | 13.2 |
| Qwen3.5-0.8B | MNN CPU | 59.1 | **19.6** |
| Qwen3.5-0.8B | MNN GPU，舊 Mesa | 65.6 | 3.1 |
| Qwen3.5-0.8B | **MNN GPU，新 Mesa** | **116.8** | 12.6（CPU 固定最高頻：13.7） |
| Qwen3-1.7B | llama.cpp CPU（原方案） | 10.7 | 7.1 |
| Qwen3-1.7B | MNN CPU | 24.2 | **9.0** |
| Qwen3-1.7B | MNN GPU，舊 Mesa | 47.1 | 2.1 |
| Qwen3-1.7B | **MNN GPU，新 Mesa** | **62.1** | 6.9（CPU 固定最高頻：7.1） |

- **正確性**：Qwen3-1.7B 用 greedy 解碼，CPU 和 GPU（新 Mesa）的輸出**逐字相同**，測了問答和家電指令各一句。
  Qwen3.5-0.8B 是多模態模型，`llm_demo` 一定要載入視覺模組，需要用 MNN_BUILD_LLM_OMNI 重新編譯才能比對，**尚未驗證**。
- 測試期間溫度最高 65 °C。
- **結論**：
  - 讀提示詞：GPU 遠快於 CPU。0.8B 的 GPU 是 CPU 的 2 倍；比起原本的 llama.cpp，0.8B 快 4.2 倍、1.7B 快 5.8 倍。
  - 逐字生成：CPU 仍然最快。
  - 最佳組合是：
    - 暖機時預讀固定的系統提示詞，以及處理長的提示詞，交給 GPU；
    - 逐字生成交給 CPU。

    MNN 不能在同一個 session 中途切換後端，所以要用兩個實例，或依情境選擇後端，**尚未實作**。

## 十、GPU 生成：逼近上限（2026-11-09 晚上）

- **讀取上限**（`cl_readbw.c`，GPU 只讀不寫）：14–17 GB/s。
  0.8B 每生成一個 token 要讀約 448 MiB 權重，所以上限約 **33–36 tok/s**。
  > **更正（見第十四節）**：14–17 GB/s 是這支測試程式同時發出的讀取不夠多造成的，不是硬體上限。改進後實測可達 **24.1 GB/s**。
  目前實測 13.0，只達到上限的約 36%。
- **每個 kernel 的 GPU 時間**（`MNN_GPU_TIME_PROFILE`，新 Mesa，0.8B 每個 token）：

  | 項目 | GPU 時間 |
  | --- | --- |
  | 模型層 GEMV（`gemv_conv_c8_buf`，186 次） | 39.7 ms |
  | lm_head（1 次） | 23.0 ms |
  | linear attention | 5.2 ms |
  | 其他小運算 | 約 6 ms |
  | **GPU 忙碌合計** | **約 74 ms** |
  | 實際每個 token | 約 79 ms |

  **呼叫開銷只剩約 5 ms，瓶頸已經變成 GEMV kernel 本身。**
- **排除掉的假設**（都有量測佐證）：
  - **GPU 時脈**：解碼時本來就跑在 710 MHz。先前看到 257 MHz 是閒置時的讀數，是我看錯了。固定最高頻率後 13.07 → 13.09，沒有差別。
  - **計算精度**：fp32 和 fp16 差不多（12.6 vs 13.2）。
  - **讀取指令**：`vload16` 在 `uchar*` 上確實只有 8.8 GB/s，對齊後的 `uint4` 讀取可到 16.9 GB/s。
    但把 MNN 改成對齊讀取（`LOAD_W16`，執行時檢查位址、不對齊就退回原本的讀法）後，只有 lm_head 從 23.0 降到 19.8 ms，模型層沒有改善。
    而且一半的 GEMV 變體權重走的是 image，不經過這條路徑。
  - **除法**：把迴圈內 `/coef` 換成乘以倒數，有小幅改善，輸出完全相同。但就算把反量化整個拿掉，單獨測試仍是理想值的 3 倍時間。
  - **half 內迴圈加指數技巧**：沒有變快，所以不是算力瓶頸。
  - **權重改用 image 走 texture cache**：在這個驅動上反而比較慢。
- **自寫 GEMV**（`gemv_custom.cl`）：
  - 設計：每 64 條執行緒處理 8 列 × 8 個 K 切片；權重用對齊的 `uint4` 讀取；反量化以 64 個值為一個 block 分解計算；累加用 float。
  - 用 MNN 原始 kernel 的輸出做比對：最大差異 0.016–0.03，輸出值的大小約 12–20，屬於 fp16 捨入誤差。

  | 矩陣 | MNN 原版 | 自寫 kernel | 倍數 |
  | --- | --- | --- | --- |
  | 1024→3584 | 399–427 µs | 243–267 µs | 1.5–1.6× |
  | 3584→1024 | 352 µs | 274–292 µs | 1.2–1.3× |
  | 1024→1024 | 162–180 µs | 123–130 µs | 1.3–1.4× |
  | lm_head 1024→248320 | 21.9 ms | **10.5 ms（12 GB/s）** | **2.1×** |

- **推估（尚未整合進 MNN、尚未實測）**：每個 token 約 79 ms → 約 50 ms，也就是 0.8B 約 **20 tok/s**，和 MNN CPU 的 19.6 相當。
  小矩陣仍然只有約 7 GB/s，比較可能是平行度不足、藏不住記憶體延遲，還有空間。
- 這些修改目前都只在手機的 MNN 原始碼樹裡（`LOAD_W16`、`MNN_KERNEL_TRACE`），**還沒整合自寫 kernel**。

## 十一、自寫 GEMV 整合進 MNN（**實機已驗證**）

- 新增 `gemv_q4_razer_buf.cl`，並在 `ConvBufLowMemoryExecution::tuneGemvLowMemory` 接管，條件是：4-bit、非對稱、input 是 image1d、形狀對齊。
  權重是 image 或 buffer 都支援。`MNN_RAZER_GEMV=0` 可以退回原版。程式碼和套用腳本在 `experiments/voice-hub/gpu/`。
- **正確性**：Qwen3-1.7B 用 greedy 解碼，GPU 的輸出和 CPU 逐字相同。
- **速度**（暖機後，tok/s）：

  | 模型 | MNN 原版 GPU | 自寫 GEMV（S=8） | 再加上推理期間 CPU 不降頻、不深度睡眠 | MNN CPU |
  | --- | --- | --- | --- | --- |
  | Qwen3.5-0.8B | 13.1 | 17.9 | **21.4** | 19.6 |
  | Qwen3-1.7B | 6.8 | 8.3 | 8.8 | 9.0 |

  S=16 和 S=4 都比 S=8 慢。讀提示詞的速度沒有變（0.8B 約 118）。測試期間溫度最高 67 °C。
- **0.8B 每個 token 的 GPU 時間**（約 46 ms）：

  | 項目 | 時間 | 說明 |
  | --- | --- | --- |
  | 模型層 GEMV | 24.7 ms | 約 13 GB/s，是上限的 77% |
  | lm_head | 10.1 ms | 12.6 GB/s |
  | gated delta rule | 5.1 ms | |
  | Raster | 2.3 ms | 414 次 |
  | flash decode | 1.8 ms | |
  | 其他小運算 | 約 1.6 ms | |

  CPU 調成最高效能後，每個 token 實際約 46.7 ms，代表已經幾乎被 GPU 時間卡住。
- **要達到 25 tok/s（每個 token 40 ms）還需要**：
  - gated delta rule kernel：理論上約 1.2 ms，目前 5.1 ms；
  - 減少 Raster 和小運算（運算融合）；
  - lm_head 和模型層 GEMV 再逼近頻寬上限。
- 正式服務要用 PM QoS（`/dev/cpu_dma_latency`），並在推理期間暫時調高大核的最低頻率，**不能**全域關閉深度睡眠。這部分**尚未實作**。

## 十二、8-bit GEMV、lm_head coalesced、gated delta rule，以及數值正確性（**實機已驗證**）

- **1.7B 的 lm_head 是 8-bit**（`QUANT_BIT=8`），原本退回 MNN 原版 kernel，要 44 ms。
  新增 `gemv_q8_razer` 之後降到 26.8 ms（11.6 GB/s）。
- **超寬輸出（oc ≥ 65536）改走 coalesced 讀取順序**（`RZ_COAL`，S=4）：0.8B 從 21.4 升到 21.9。
- **gated delta rule decode kernel**（`linear_attn_gdr_decode_rz`）：
  每個 work-group 負責一個 head，相鄰執行緒讀相鄰的 state，只做兩次 4 路歸約。0.8B 從 21.9 升到 23.4（fp16）。
- **途中自己引入、已修正的 bug**：
  1. `LOAD_W16` 放在條件區塊內，導致原版 GEMV 在部分情況下編譯失敗；
  2. 新 GDR kernel 沒有加 `RZ_CT` 條件保護，導致原版 GDR 編譯失敗、程式 segfault。

  兩個都修好後，三種組合都 0 個編譯失敗。
- **數值正確性**（`llm_logits_diff`，以 CPU 的軌跡為準，48 步）：

  | 情境 | CPU 對 GPU 原版：KL | CPU 對 GPU razer（fp16）：KL | CPU 對 GPU razer（fp32）：KL |
  | --- | --- | --- | --- |
  | 0.8B 家電指令 | 0.131 | 0.132 | **0.010** |
  | 0.8B 地理介紹 | 0.220 | 0.217 | **0.017** |
  | 1.7B 家電指令 | 0.091 | 0.095 | 0.089 |
  | 1.7B 地理介紹 | 0.088 | 0.088 | 0.087 |

  - 自寫 kernel 的誤差和 MNN 原版 GPU 相同，**沒有額外引入誤差**。
  - 0.8B（Qwen3.5 混合架構）在 GPU fp16 下明顯退化：teacher-forced NLL 從 0.27 → 0.48、0.93 → 1.28。
    改用 GPU fp32 後回到 0.29 和 0.94，接近 CPU。
  - 1.7B 的 KL 來源主要是 CPU 本身的 fp16（`precision=low`），GPU 的 NLL 反而比較低。
- **最終速度**（推理期間 CPU 效能模式，暖機後，tok/s）：

  | 模型 | GPU fp16 | GPU fp32 | MNN CPU |
  | --- | --- | --- | --- |
  | Qwen3.5-0.8B 生成 | **23.4** | **22.0** | 20.3（另一次量測 21.5） |
  | Qwen3.5-0.8B 讀提示詞 | 117.6 | 76.0 | 59.2 |
  | Qwen3-1.7B 生成 | **10.5** | 9.9 | 8.8 |
  | Qwen3-1.7B 讀提示詞 | 58.3 | 32.5 | 23.8 |

  溫度：GPU 最高 70 °C，CPU 最高 78 °C。
- **建議**：
  - 0.8B 用 GPU fp32：準確度接近 CPU，生成比 CPU 快 2–8%，讀提示詞快 28%，溫度也比 CPU 低。
  - 1.7B 用 GPU fp16：生成比 CPU 快 20%，讀提示詞快 2.4 倍。
- 從最初的 3.1 tok/s（0.8B，舊驅動）一路提升到 22–23 tok/s。

## 十三、GEMV 二維切分（0.8B 達到 25 tok/s，**實機已驗證**）

- **單獨測試**（`gemv_2d.cl`，GPU 固定 710 MHz）：每列 8 個輸出用 SB（跨 quant block）× SC（block 內部）條執行緒分工。
  **SB=8、SC=2** 在 6 種實際形狀都是最好或接近最好，比原本的 SB=8、SC=1 快 1.3–1.5 倍；1024→6144 達到 14.4 GB/s，約上限的 85%。
- **整合方式**：模型層用 SB=8×SC=2；超寬輸出（lm_head）用 SB=1×SC=4，也就是原本的 coalesced 讀法。
  歸約改成樹狀。可用環境變數 `MNN_RAZER_GEMV_SB/SC(_BIG)` 調整。
- **正確性**：和 CPU 比較的 KL 與修改前相同。0.8B：fp16 0.229、fp32 0.017；1.7B：fp16 0.088、fp32 0.087。
- **速度**（CPU 效能模式，tok/s）：

  | 模型 | GPU fp16 | GPU fp32 | 讀提示詞（fp16 / fp32） |
  | --- | --- | --- | --- |
  | Qwen3.5-0.8B | **25.1** | **23.9** | 118 / 76 |
  | Qwen3-1.7B | **11.2** | **10.5** | 58 / 33 |

- **0.8B 每個 token 剩下的 GPU 時間**（約 38.5 ms，實測 39.8 ms）：

  | 項目 | 時間 | 說明 |
  | --- | --- | --- |
  | 模型層 GEMV | 22.3 ms | 約 14.4 GB/s，上限的 85% |
  | lm_head | 9.2 ms | 13.8 GB/s |
  | Raster（414 次小搬移） | 2.4 ms | |
  | gated delta rule | 2.0 ms | |
  | flash decode | 1.6 ms | 每次約 260 µs，是延遲造成的下限 |
  | 其他小運算 | 約 1.9 ms | |

  矩陣乘法已經接近頻寬上限，剩下的空間主要在非矩陣的約 8 ms。
  > **更正（見第十四節）**：「接近頻寬上限」是用偏低的 14–17 GB/s 算的；以真正的 24.1 GB/s 計算，矩陣乘法只用到約 60–80%。

## 十四、重新量測頻寬上限，以及 GEMV 的真正瓶頸（**實機已驗證**）

- **記憶體頻率**：手機上的 IPA 一直沒有初始化，所以 interconnect 的 `sync_state` 一直處於 pending。
  所有匯流排因此維持開機時的最大頻寬投票（`ebi` 為 2147483647），記憶體頻率不是瓶頸。
  副作用是待機時記憶體也不會降頻，耗電較高，**尚未處理**。
- **讀取上限**（`cl_bwmax.c`，448 MiB，GPU 計時，固定 710 MHz）：

  | 讀法 | 頻寬 |
  | --- | --- |
  | 舊測試（每次同時發出的讀取太少） | 14–17 GB/s |
  | 每個 work-group 讀一段連續資料，或 global size ≥ 262144 | **24.1 GB/s**（LPDDR4X 規格 29.9 的 81%） |
  | image2d `read_imageui` | 24.1 GB/s |
  | CPU 4 顆大核 NEON（`cpu_bw.c`） | 17.9 GB/s |

  所以 0.8B 每個 token 的權重和量化係數（約 470 MB）最少要 19.5 ms。
- **GEMV 卡在哪裡**（`gemv_exp.cl` / `gemv_exp_bench.c`，lm_head 1024→248320）：

  | 版本 | 時間 |
  | --- | --- |
  | 只讀權重 | 5.35 ms |
  | 讀權重、輸入、係數，幾乎不算 | 6.70 ms |
  | 不讀權重，只運算 | 5.88 ms |
  | 完整版（現行） | 7.2 ms |

  **記憶體和運算差不多一樣慢**，兩者互相蓋不住。
  - Adreno 630 標稱的 730 GFLOPS 是半精度、而且乘加算兩次；實際 32-bit 約每秒 1,800 億個運算。
  - 每個 4-bit 權重要做「取 4 bit、轉浮點、乘加」3 個指令。
  - ir3 編譯器忽略了 `#pragma unroll`：內層迴圈沒有展開，每一圈只發出一個權重讀取。
- **試過但沒有效的改法**（如實列出）：
  - 手動展開迴圈：最多快 5–12%，最佳設定不變。
  - 半精度運算：更慢。
  - 輸入轉 16-bit 整數後用 `mad24`：小幅改善，最佳設定不變。
  - 輸入先放進 local memory：慢 2–4 倍（佔用率下降）。
  - 輸入改用一般 buffer 讀取：慢約 10%。
  - 先預讀到陣列：陣列被放到私有記憶體（`stp`/`ldp`），慢 3 倍以上。
- **採用的改動**：寬輸出（lm_head）的分工由 SB=1×SC=4 改成和其他層相同的 SB=8×SC=2（`patch_2d.py` 預設值已同步更新）。
- **驗證**（CPU 效能模式，tok/s）：

  | 模型 | 生成（fp16 / fp32） | 讀提示詞（fp16 / fp32） | KL 對 CPU（fp16 / fp32） |
  | --- | --- | --- | --- |
  | Qwen3.5-0.8B | 25.1 → **25.6** / 23.9 → **24.2** | 117 / 76 | 0.223 / 0.017（不變） |
  | Qwen3-1.7B | 11.2 → **12.0** / 10.5 → **11.3** | 58 / 33 | 0.088 / 0.087（不變） |

  1.7B 進步較多，因為它的 lm_head 是 8-bit，佔每個 token 的比例更大。
- **剩下的空間**：
  - 0.8B 的矩陣乘法目前約 30 ms，物理下限 19.5 ms。
  - 要再縮短，需要讓記憶體讀取和運算真正重疊，或合併共用同一輸入的小矩陣（例如 gate/up）來減少每次呼叫的固定開銷（約 20 µs）。後者要改 MNN 的計算圖。

## 十五、全面檢查：換框架、驅動開銷、批次送出、DTB（**實機已驗證**）

### 15.1 驅動每次啟動 kernel 的開銷（`cl_dispatch.c`）

| 項目（每個 kernel） | 預設電源設定 | CPU 效能模式 |
| --- | --- | --- |
| CPU 送出（clEnqueue） | 1.2–3.7 µs | 1.1–1.4 µs |
| 連續送出、最後才同步，平均每個 | 6–8 µs | 6–8 µs |
| GPU 端最小執行時間 | 約 3 µs | 約 3 µs |
| 開啟 profiling 時兩個 kernel 之間的空檔 | 155–370 µs | 約 80 µs |

- **CPU 不是瓶頸**：0.8B 每個 token 約 1,085 個 kernel，CPU 送出合計約 1.3 ms，而且和 GPU 執行重疊。
- **GPU 端每個 kernel 有約 6 µs 的固定成本**，全部合計約 6 ms，約佔每個 token 的 15%。
- 來源：rusticl 在每個 kernel 前後都呼叫 `memory_barrier`，freedreno 會轉成 WFI；用到 image 的 kernel 還要再清一次快取。
  這是依序佇列保證正確性的必要步驟，不能直接拿掉。
- **profiling 會讓空檔放大 10–50 倍**，所以 `MNN_GPU_TIME_PROFILE` 只能看每個 kernel 的時間，不能看總時間。
- **真正有效的「批次化」是減少 kernel 數量**（MNN 每個 token 有 414 次 Raster 搬移），要改 MNN 的計算圖，**尚未做**。

### 15.2 DTB／核心設定檢查（`dt_audit.sh`）

| 項目 | 狀態 |
| --- | --- |
| GPU OPP | 257–710 MHz，沒有 speed-bin 限制；710 MHz 是 SDM845 主線的最高頻率 |
| 記憶體頻寬 | interconnect `sync_state` 因 IPA 沒初始化而 pending，一直維持最大投票 |
| LLCC 系統快取 | `qcom-llcc` 已綁定 |
| GPU IOMMU | 延後一次後正常初始化 |
| 溫控 | 推理時沒有觸發 |
| 大核 2.8 GHz boost | DT 有這個 OPP，但 `cpufreq/boost=0` 沒有開啟 |

- boost 實測（`boost_ab.sh`）：CPU 生成 20.2 → 20.5，讀提示詞 60.5 → 59.3，GPU 不變，溫度多 7 °C。
  **沒有實質效益，維持關閉。**
- 結論：**DTB 沒有拖慢推理的設定錯誤。**

### 15.3 換推理框架

- **Vulkan 系框架（llama.cpp Vulkan、ncnn、ExecuTorch 等）**：Turnip 在 a630 回報 `storageBuffer8BitAccess` 和 `storageBuffer16BitAccess` 都是 false，多數框架需要這兩項。
- **llama.cpp OpenCL：已讓它在 GPU 上執行**
  - Mesa 26.2.6 的 rusticl 已提供 `__opencl_c_subgroups` 和 `cl_khr_subgroup_*`，但規範上不列出 `cl_khr_subgroups` 這個名稱。
    `patch_llama_subgroups.py` 放寬了 llama.cpp 的這項檢查。
  - kernel 是靠 `cl_qcom_*` 擴充判斷 Adreno。`patch_llama_rusticl_defs.py` 在 `GGML_OPENCL_RUSTICL_ADRENO=1` 時補上巨集，並把 `qcom_sub_group_shuffle_xor` 對應到標準函式。
    另外以 `IR3_SHADER_DEBUG=thread64` 固定 subgroup 為 64。
  - `patch_llama_kernels_rusticl.sh` 修正一個依賴高通編譯器寬鬆指標規則的 kernel。
  - **正確性**（`test-backend-ops` 對 CPU）：MUL_MAT、RMS_NORM、ROPE、SOFT_MAX、GET_ROWS、ADD、MUL、GATED_DELTA_NET、SSM_CONV、FLASH_ATTN_EXT 已跑的案例全部通過。
    MUL_MAT 和 FLASH_ATTN_EXT 在 40 分鐘時限內沒跑完。CPY 有 1 個轉置案例失敗。
  - **速度**（tok/s）：

    | 模型 | llama.cpp OpenCL 讀提示詞 / 生成 | MNN + 自寫 kernel 讀提示詞 / 生成 |
    | --- | --- | --- |
    | Qwen3.5-0.8B Q4_0 | 41 / **2.0** | 118 / **25.6** |
    | Qwen3-1.7B Q4_0 | 20 / **1.8** | 58 / **12.0** |

    1.7B 的模型結構較單純，也一樣慢，表示問題不在運算退回 CPU，而是 llama.cpp 的 4-bit 矩陣乘法在 rusticl 上很慢。
- **結論：換框架沒有好處。** 任何框架都受同樣的 24.1 GB/s 頻寬和 ALU 限制，目前 MNN 加自寫 kernel 是最快的。

### 15.4 能不能從驅動／硬體層面加速 4-bit 解碼（`alu_tp.cl`、`cl_tmu.c`）

- 4-bit 矩陣乘法程式在推理框架裡（MNN 用的是我們自寫的 `gemv_q4_razer`），不在驅動裡。驅動能影響的是編譯器 ir3 產生的指令，以及紋理單元等硬體資源。
- **計算單元實測**（710 MHz，每秒處理的權重數）：

  | 做法 | 每秒 | 相對純乘加 |
  | --- | --- | --- |
  | 純乘加（下限） | 1,090 億 | 1× |
  | 只做整數取 4 bit | 630 億 | 1.7× |
  | 現行：取 4 bit + 轉浮點 + 乘加 | 468 億 | 2.3× |
  | 把 4 bit 移進尾數再 OR 指數（避開轉換指令） | 291 億 | 3.7×（ir3 沒有合併成 `shlm`，反而更慢） |

  lm_head 2.54 億個權重光解碼就要約 5.4 ms，比讀記憶體（5.35 ms）還久。
- **紋理單元實測**（讀取時硬體免費轉換格式）：

  | 格式 | 頻寬 | 紋素/秒 |
  | --- | --- | --- |
  | RGBA32UI | 24.1 GB/s | 15 億 |
  | RGBA8 UNORM | 15.9 GB/s | 40 億 |
  | RGBA16 UNORM | 22.2 GB/s | 28 億 |
  | R8 UNORM | 4.6 GB/s | 46 億 |

  紋理單元每秒最多約 40–46 億紋素，用它解碼會讓頻寬掉到 15.9 GB/s，比現行 GEMV 的實際約 17.6 GB/s 還慢。
  OpenCL 沒有 4-bit 紋理格式（R4G4B4A4），即使替 rusticl 加上，也需要每秒約 120 億紋素，超過硬體能力。
- **結論**：4-bit 解碼的運算成本是硬體本質，驅動層沒有能大幅改善的地方。
  理論上若記憶體讀取和運算能完美重疊，GEMV 還可再快約 25%（7.2 → 5.4 ms），但這取決於 GPU 內部排程，目前試過的寫法都沒有達到。

### 15.5 剩下真正有空間的地方

| 方向 | 估計可省 | 工作量 |
| --- | --- | --- |
| 減少 kernel 數量：Raster 搬移、合併小運算 | 3–5 ms（約 10%） | 改 MNN 計算圖 |
| 合併共用同一輸入的小矩陣（gate/up、q/k/v） | 2–3 ms | 改 MNN 計算圖 |
| 讓記憶體讀取與運算真正重疊 | GEMV 上限約可再省 20% | 研究性質，不確定 |

### 5.3 HA token

- 新增 `experiments/voice-hub/ha.env.example`。
- 使用者複製成 `ha.env` 並填好後，由我用 scp 放到手機的 `~/.config/razer-voice/ha.env`，權限設為 600。
- `ha.env` 已加入 `.gitignore`。
