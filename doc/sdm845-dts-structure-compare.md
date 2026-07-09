# SDM845 板級 DTS 結構對照與 Razer Phone 2 缺口分析

## 1. 這一輪複製出的輸出物，是否和上一輪不同？

註：自 2026-04-22 起，USB bring-up 的 debug-safe 設定已開始收斂回工作區原始 DTS 與 build script 驗證邏輯，方向是不再依賴只存在於 WSL kernel tree 的隱式 DTS 覆寫。

能確認的是：目前 `output/debug` 內的產物是重新生成過的新檔，不是單純重複複製。

- `boot-debug.img`: 2026/4/21 18:31:46，約 15.02 MB
- `Image.gz-dtb`: 2026/4/21 18:31:40，約 14.05 MB
- `kernel-debug.config`: 2026/4/21 18:31:40，約 0.23 MB
- `build-debug.log`: 2026/4/21 18:31:40，約 0.17 MB
- 同目錄還有 `Image.gz`、`initramfs-debug.cpio.gz`、`busybox-aarch64`

工作區內沒有找到其他同名 `boot-debug.img`、`Image.gz-dtb`、`kernel-debug.config`、`build-debug.log` 副本，因此無法直接在工作區內做「上一輪 vs 這一輪」二進位比對；但從修改時間可確認，現在 `output/debug` 裡的是新一次 build 產物。

另一個容易混淆的點：

- 工作區原始檔 `dts/sdm845-razer-aura.dts` 仍然保留原本的 `dr_mode = "otg"` 與 `maximum-speed = "super-speed"`。
- 真正用來打包 debug boot 的 USB 降階設定，是 build script 在 kernel tree 內暫時覆寫後再編進 DTB，不是直接改工作區這份 DTS 原始檔。

這代表「輸出 boot 確實有更新」與「工作區原始 DTS 看起來沒變」可以同時成立。

## 2. include 展開後，SDM845 手機板級 DTS 可以分成哪些結構層？

完整展開後的檔案會很長，但結構大致固定，可以拆成四層：

1. `sdm845.dtsi`
   - SoC 本體：CPU、GIC、TLMM、GCC、QUP、UFS、USB、MDSS、remoteproc、reserved-memory 預設區塊。
2. `sdm845-wcd9340.dtsi`
   - WCD9340 / Slimbus 音訊基礎節點。
3. `pm8998.dtsi` 和 `pmi8998.dtsi`
   - PMIC、charger、WLED、flash、PMIC GPIO、RPMh regulator 基礎節點。
4. 板級 `.dts` 或 common `.dtsi`
   - 真正描述手機差異的地方：面板供電、觸控 reset/irq、USB 模式策略、額外 PMIC、相機、NFC、喇叭擴大器、板級 reserved-memory 覆寫、firmware 路徑等。

因此，判斷某份手機 DTS 是否「資訊不夠」，重點不在 include 數量，而在第 4 層是否把板子自己的電源樹、周邊和路由描述完整。

## 3. 參考板的板級結構總結

### OnePlus 6 / 6T common

特徵：

- `chosen` 下面除了 simple-framebuffer，還加了 fake panel 節點，專門處理 simpledrm / msm-drm probe ordering。
- 有 hall sensor、alert slider、gpio-keys 等板級輸入裝置。
- `reserved-memory` 不只保留 `rmtfs_mem`，還多了 `removed_region` 和 `ramoops`。
- 板級固定 regulator 很多，明確描述觸控、面板、相機各自的 GPIO-controlled rail。
- 有完整 CAMSS / CCI / camera / actuator 結構。
- 有 NFC、觸控細節、對應 pinctrl 狀態。
- USB 部分直接把 `usb_1_dwc3` 壓成 `peripheral` + `high-speed`，並只保留 HS PHY，這是一個「先讓 USB 穩定工作，再談 Type-C/USB3」的 bring-up 策略。

### Xiaomi Beryllium common

特徵：

- 在頂層補了 `qcom,board-id`、`qcom,msm-id`、`chassis-type`。
- 大量刪除並重建 `reserved-memory`，包含 `tz_mem`、`adsp_mem`、`wlan_msa_mem`、`mpss_region`、`venus_mem`、`cdsp_mem`、`mba_region`、`slpi_mem`、`spss_mem`、`rmtfs_mem`。
- `apps_rsc` regulator 覆寫完整，許多電壓被明確固定。
- 面板依賴 `lab` / `ibb`，代表板級顯示電源樹不只一般 1.8V / 3.3V。
- 有 CAMSS、CCI、camera sensor、actuator 與對應 pinctrl。
- USB 也是先用 `dr_mode = "peripheral"`。

### Samsung S9 common

特徵：

- 頂層有 `model`、`compatible`、`chassis-type`。
- `chosen` simple-framebuffer 直接掛實際供電 rail。
- 板上多了一顆外掛 PMIC `s2dos05`，透過 `i2c-gpio` 描述，並用來供應面板與觸控。
- 還有外掛 speaker amp `max98512`、haptic regulator、PWM vibrator、LED、額外按鍵。
- 顯示、觸控、音訊、GPIO-I2C 外掛器件都不是只靠 SoC/PMIC 預設節點，而是明確寫成板級結構。
- USB 先強制 `peripheral`，註解明講「在 Type-C 還沒接好之前先這樣跑」。

## 4. 目前 Razer Phone 2 這份 DTS 已經覆蓋了哪些大類？

Razer 這份檔案其實不算空，已經有相當多板級內容：

- 頂層識別：`model`、`compatible`、`chassis-type`、`qcom,msm-id`
- `chosen` / simple-framebuffer
- `gpio-keys`
- `battery`
- `reserved-memory` 中的 `rmtfs_mem` 與 `ramoops`
- 自建固定 regulator：`vph_pwr`、`vreg_s4a_1p8`、觸控 1.8V、panel VCI / POC
- `apps_rsc` / `pmi8998` regulator 覆寫，內容其實比很多最小 bring-up DTS 還完整
- GPU / IPA / modem / ADSP / CDSP / SLPI firmware 路徑
- 觸控節點
- Dual-DSI 面板節點與 pinctrl
- UFS
- 音訊 card / codec / Bluetooth / WiFi
- USB HS/SS PHY 供電與 PHY tuning

所以問題不是「整份 Razer DTS 太短太空」，而是某幾個會控制實機 bring-up 的板級子系統，還不像參考板那樣完整或保守。

## 5. 和參考板相比，Razer 最可疑的缺口在哪裡？

### A. USB 路徑雖然有寫，但板級策略還不夠保守

目前工作區原始 DTS 的 USB 仍是：

- `dr_mode = "otg"`
- `maximum-speed = "super-speed"`
- 保留 QMP USB3 PHY

但 OnePlus 與 Samsung 在 bring-up 階段都採取更保守的策略：

- 強制 `peripheral`
- 優先 USB2 `high-speed`
- 在 OnePlus 上甚至直接去掉 USB3 PHY，只留 HS PHY

你現在的 debug build 已經在 script 裡把 kernel-tree copy 暫時改成這種模式，但原始 DTS 還沒有形成一份明確、可追蹤的「debug-safe USB board description」。

這件事很重要，因為你現在的症狀是：

- 螢幕閃一下就黑
- Windows 沒有任何新 USB 裝置
- 沒有 COM port

這比較像是 USB 板級 bring-up 沒有進入穩定 peripheral 狀態，而不是 initramfs gadget 腳本本身有沒有寫到位的問題。

### B. 顯示供電描述可能仍然不完整

Razer 面板目前只明確描述三條板級供電：

- `vddio-supply`
- `vci-supply`
- `poc-supply`

但參考板顯示供電常見的情況是：

- 會額外用 `lab` / `ibb` 這類正負偏壓 rail
- 或像 Samsung 那樣，面板 rail 其實來自外掛 PMIC，而不是只靠主 PMIC 預設輸出

如果 Razer 原始 Android 板級其實還有額外 bias rail、load switch、GPIO expander、外掛 PMIC 或面板初始化依賴，而目前主線 DTS 沒寫出來，那就可能出現「bootloader 能亮一下，Linux 接手後很快失去 panel 電源或時序」的症狀。

### C. reserved-memory 只做了最小覆寫

Razer 現在只明確重建：

- `rmtfs_mem`
- `ramoops`

但 Beryllium 這類參考板會把 downstream firmware 相關記憶體區域整批對齊。這類缺口通常比較影響：

- modem
- ADSP / CDSP / SLPI
- Venus
- WLAN

它未必是目前「一開機就黑、USB 不枚舉」的第一嫌疑，但代表這份 Razer DTS 還停留在「先讓核心外設勉強起來」的層次，不是已經把整個 downstream memory topology 還原完整。

### D. 缺少更明確的板級外掛器件與旁路電源樹資訊

和 Samsung / OnePlus 比，Razer 目前看不到下列類型的板級器件描述：

- 外掛顯示 PMIC 或 bias PMIC
- 額外的 GPIO-I2C board devices
- haptics / vibrator 的具體電源與控制路徑
- NFC / 其他感測器 / hall 類週邊
- 相機與 CAMSS 相關板級 wiring

這些不一定是當前 boot blocker，但它們說明了一件事：目前 Razer DTS 仍然比較像「把已知幾個關鍵外設搬進來」，不是「完整還原整塊手機主板的板級描述」。

## 6. 對目前黑屏 + 無 USB 症狀，最值得優先懷疑的是哪兩類？

如果只針對現在的失敗症狀排序，優先級我會這樣排：

1. USB 板級模式與路由
   - 不是 configfs gadget 腳本，而是更前面的 DWC3 / PHY / 模式選擇還沒進入穩定 peripheral attach 狀態。
   - 目前參考板經驗支持「先把 USB3/OTG 複雜度全部拿掉」這個方向。

2. 面板實際供電樹或時序仍缺資訊
   - 目前面板 node 已存在，但可能還少真正的電源 rail、偏壓或特定 reset / enable 次序依賴。

`reserved-memory`、相機、感測器、NFC 這些比較像後續完整化項目，不像目前無 USB 枚舉的第一根因。

## 7. 目前最合理的結論

結論不是「Razer DTS 幾乎沒寫」，而是：

- 已經有不少板級內容，尤其 regulator、面板、觸控、WiFi、音訊、UFS 都有初步描述。
- 但和成熟的 SDM845 手機板級 DTS 相比，Razer 仍缺少一些讓 bring-up 變穩定的板級保守策略與外掛電源/器件資訊。
- 對眼前症狀最相關的，仍然是 USB 路徑與顯示供電/時序，不是單純再多加一點 initramfs 診斷字串就會解決。

## 8. 下一步應該怎麼做

最合理的不是再盲目重包一次，而是分成兩件事：

1. 把目前 build script 內的 USB debug patch 正式整理成一份可追蹤的 board-level debug DTS 變體，避免工作區 DTS 與實際打包進去的 DTB 長期脫節。
2. 回頭對照 Razer Android 原始板級資料，專找面板電源樹、USB Type-C/PMIC 路由、以及是否存在額外 panel bias / external regulator / load switch。

如果只能先做一件事，優先做第 2 件，因為它最可能直接解釋「閃一下就黑，且完全沒有 USB 枚舉」。