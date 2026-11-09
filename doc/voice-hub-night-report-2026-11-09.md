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

### 5.3 HA token

- 新增 `experiments/voice-hub/ha.env.example`。
- 使用者複製成 `ha.env` 並填好後，由我用 scp 放到手機的 `~/.config/razer-voice/ha.env`，權限設為 600。
- `ha.env` 已加入 `.gitignore`。
