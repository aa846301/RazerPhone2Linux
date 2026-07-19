# Razer Phone 2 Linux

[English](README.md)

這是 Razer Phone 2（`aura`、Qualcomm SDM845）的 mainline Linux 專案。預設
release 是不預裝應用程式的硬體平台映像：能驅動 GPU、WiFi、充放電保護、
螢幕休眠，讓使用者自己安裝需要的軟體。

## 目前狀態

- Kernel baseline 是 SDM845 mainline `sdm845/7.1-dev`，固定在
  `85f1df2a4ec7`（`7.1.0-rc1`）。
- NT36830 原生 dual-DSI/DSC 顯示路徑已透過 opt-in native-panel build
  實作；DSI/DSC 設定已對齊 Razer LK factory 行為。
- Adreno 630 可透過 freedreno 使用硬體 GL；需要 stock Razer
  `a630_zap.*` 與 linux-firmware `a630_sqe.fw`。
- PMI8998 SMB2 charger、fuel gauge、RRADC 已啟用。rootfs service 會透過
  標準 `charge_behaviour` power-supply 介面，在電量高於 40% 時優先使用外部
  輸入；電量降到 40% 會開始一輪充電，持續充到 80% 才停止。DTS 仍保留
  保守的 2 A 充電限制。
- 預設正常開機會在 rootfs 起來後讓面板進入 blank；console mode 仍可用於
  顯示除錯。正常關機會在硬體停止前恢復真實 tty/kernel log。
- 系統會透過 `qbootctl` 標記 Qualcomm A/B 開機完成，避免正常重開機耗盡
  目前槽位的 retry count。
- USB NCM 網路與 SSH 可由 `192.168.137.133` 連線。
- WiFi 透過 MSS/WLFW、`rmtfs`、userspace `pd-mapper`、patched
  `tqftpserv`、Razer FIH NV sharing 與 ath10k host-capability quirk 運作。
- 後置 IMX363 已在實機證實能經 CSI/VFE 輸出 RAW10；1920×1080 mode 的
  四像素週期條紋來自不完整的 sensor mode table，不是 CSI lane packing。
  4032×3024 完整模式沒有該相位錯誤，測試面板先以此模式預覽、拍照並套用
  簡易白平衡。前置 S5K3H7 的三路電源、reset 與 24 MHz MCLK 都已送出，但
  CCI1 晶片 ID 仍回 NACK。原廠 `retries=3` 的位元編碼已確認，但現有
  `0014` 將它無條件套到所有 CCI 裝置，不視為最終解法；待改成
  S5K3H7 裝置層 retry，或預設為 0 的可選 CCI 設定。
- PMI8998 LRA 已套用原廠 1300 mV／800 mA 限制，並由實機觸感確認震動有效。
  音訊已接上 WCD9340/SLIMbus、原廠雙 TFA9912 與 `tfa98xx.cnt`；原廠呼叫鏈
  顯示 QUAT 必須使用 SD1 立體聲。最新實機已確認 GPIO61/SD1 output-high
  與 Q6ASM IOVA 限制生效，但播放時兩顆功放的 `CLKS/PLLS` 仍為 0，目前無聲。

## 硬體支援清單

以下分類參考 postmarketOS 裝置頁常用的功能項目。打勾代表已在實機驗證；
部分完成的功能會拆開列出，讓剩餘工作保持清楚。

- [x] 開機與 fastboot 刷機
- [x] Qualcomm A/B 開機成功標記
- [x] 內部 UFS 儲存與 rootfs
- [x] 原生 dual-DSI/DSC 顯示與觸控
- [x] 開機後面板 blank 與關閉背光
- [x] 電源鍵、音量鍵與 Linux 正常關機流程（接著 VBUS 時可能再次冷開機）
- [x] Adreno 630 GPU 硬體加速與專有韌體
- [x] USB NCM 網路與 SSH
- [x] WiFi 掃描、連線與重新連線
- [x] 電池電量、電壓、電流與溫度資訊
- [x] 有線充電、USB-PD sink 協商與 RRADC 輸入量測
- [x] 外部供電優先的 40-80% 充電策略
- [x] 藍牙韌體、控制器初始化與裝置掃描
- [ ] 藍牙配對與重新連線驗證
- [ ] 藍牙音訊
- [ ] 系統 suspend 與深度休眠（目前僅支援面板 blank）
- [ ] 喇叭、麥克風、聽筒與 USB-C 音訊
- [x] 後相機 RAW10 感測器、CSI/VFE 與診斷預覽
- [ ] 前相機、3A、拍照與錄影
- [ ] GNSS/GPS
- [ ] Modem 通話、SMS 與行動數據
- [ ] NFC
- [ ] USB OTG/host mode
- [ ] USB 3 SuperSpeed 資料傳輸（目前 fastboot 使用 USB 2）
- [ ] DisplayPort alternate mode
- [ ] 加速度計、陀螺儀、磁力計、距離與環境光感測器
- [x] 震動馬達
- [ ] notification/Chroma LED
- [ ] 指紋辨識
- [ ] Qi 無線充電
- [ ] 全磁碟加密整合

## 最新實機錯誤邊界（2026-07-19）

本輪重刷後的實機核心為
`7.1.0-rc1-sdm845 #1 SMP PREEMPT Sat Jul 18 17:45:53 UTC 2026`。
以控制面板與 `scripts/diagnostics/` 內的測試重現後，目前確定的
最後成功階段與最早失敗邊界如下。

### 前鏡頭 S5K3H7

- 三路電源、reset、24 MHz MCLK 與 CCI1 400 kHz 設定已送出。
- 不變的錯誤是第一次讀取 chip-ID register `0x0000` 就回傳
  `Error reading reg 0x0000: -6`、`failed to read chip id: -6` 與
  `error -ENXIO: failed to find sensor`。
- 包含原廠 `retries=3` 的新核心仍收到 CCI NACK，還沒進入 sensor
  mode table、CSI 串流或面板預覽。
- 下一個有判別力的驗證是量測模組端 VANA/VDIG/VIO、24 MHz MCLK、
  reset 與 CCI SDA/SCL 實際波形，不應修改尚未執行的 mode table。

### 雙 TFA9912 喇叭

- ALSA PCM 已為 `RUNNING`，格式是 48 kHz、S16_LE、stereo；MultiMedia1 到
  QUAT MI2S 的 route 與左右 TFA9912 DAPM 都是 `On`。
- GPIO58/BCLK、GPIO59/WS 與 GPIO61/SD1 都是 `out func1`，GPIO60/SD0 是
  `in func1`，已與原廠 pin direction 一致。
- Q6ASM log 的 `0x11ff80000` 包含高 32-bit 的 `SID=1`；實際 IOVA 是
  `0x1ff80000`，已落在原廠 `0x10000000..0x1fffffff` 視窗內，且本輪
  沒有再出現 ASM memory-map timeout。
- 兩顆 TFA9912 都執行 `tfa_dev_start success`，但播放期間 status register
  `0x10` 仍為 `0x001c`：`PLLS=0`、`CLKS=0`、`SWS=0`、`AMPS=0`、
  `AREFS=0`。
- 目前最早未成立的階段是「QUAT MI2S bit clock/reference 實際到達
  TFA9912」，不再是控制面板、mixer route、ALSA PCM、DMA window 或
  GPIO61 方向。下一步應量測 GPIO58/59/61 波形，並對照 Q6AFE clock
  request/response。

開機期間仍可見 `PDR: service lookup for avs/audio failed: -6` 與一次
`QMI wait timeout`，但 fallback 後 SLIMbus、ALSA 與播放 backend 已成立；
這兩項不是本輪無聲的最早阻斷點。

## 驅動修改作用域稽核（2026-07-19）

此稽核涵蓋正常建置會套用的 `kernel-patches/0001` 至 `0015`，以及
`panel-driver/panel-novatek-nt36830.c`。判斷不只看功能是否碰巧啟動；
每個驅動層修改都必須依下列順序檢查：

1. 先確認 mainline Linux 是否已有驅動、標準 binding 或可由 DTS 表達的功能。
2. 確認網路上的上游或現有移植方案，記錄版本、裝置變體與尚未解決的差異。
3. 先列出電壓與負載、電源時序、clock、reset、GPIO/pinctrl、bus 地址與
   速率、interrupt、DMA/IOMMU、reserved memory、firmware/calibration、晶片專屬
   register/profile 與 userspace ABI。
4. 從原廠 production source 追完 probe 到實體輸出的調用鏈，逐項比對，
   不得用其他 SDM845 機型或未使用的原廠 DTS 填補未知值。
5. 判斷參數屬於 SoC 通用、controller、bus、單一晶片或單一板級。
   Razer 專屬行為必須由精確 compatible、match-data 或預設不改變的 DTS
   opt-in 限定，不能以幾何參數或全域 hardcode 間接辨識 Razer。

### 必須重做或縮小作用域

| 項目 | 稽核結論 | 後續要求 |
| --- | --- | --- |
| [`0003` DSI/DSC](kernel-patches/0003-drm-msm-align-dsc-and-dsi-with-razer-lk-ground-truth.patch) | 以 DSC 幾何辨識 Razer，而且有些 DSI 設定無條件影響所有 command-mode DSC 面板。 | 把 LK magic values 移到由 `razer,aura-nt36830` 選中的 panel/bridge/SoC quirk，保留通用 DSI/DSC 原行為。 |
| [`0011` Q6ASM DMA mask](kernel-patches/0011-asoc-q6asm-limit-dma-address.patch) | 無條件把所有 Q6ASM 限成 29-bit；此 mask 只限制上界，不保證原廠 `0x10000000..0x1fffffff` 下界。 | 先確認這是 firmware IOVA window 還是 DMA capability，再用 `dma-ranges`、IOMMU/reserved DMA pool 或精確 match-data 表達。 |
| [`0012` CAMSS notifier](kernel-patches/0012-media-qcom-camss-register-bound-sensors.patch) | 每 bind 一顆 sensor 就註冊 subdev nodes，改變通用 CAMSS lifecycle，並可能重複註冊。 | 修好前鏡頭 probe；排障時可暫時在 DTS disable 未工作的 sensor，不保留這個通用 workaround。 |
| [`0014` CCI retries](kernel-patches/0014-i2c-qcom-cci-use-factory-transaction-retries.patch) | `retries=3` 編碼與原廠一致，但現在影響所有 CCI sensor。 | 改成 S5K3H7 chip-ID 裝置層 retry，或可由特定 CCI/device opt-in 且預設為 0 的控制器設定。 |

### 方向合理，但必須補證據或限制

| 項目 | 已確認的部分 | 仍需追蹤 |
| --- | --- | --- |
| [`0001` MSS/FIH NV](kernel-patches/0001-remoteproc-qcom-share-razer-fih-nv-with-mss.patch) | 由 DT opt-in，未指定的板子不改變。 | 補 binding，重新命名過度綁定 FIH 的屬性，並確認 stop/remove 時的 memory ownership lifecycle。 |
| [`0002` DSI clock override](kernel-patches/0002-drm-msm-dsi-honor-factory-clk-post-pre-override.patch) | 有 DT opt-in，原廠數值可追溯。 | 參數應歸屬 panel/mode 或文件化的 PHY tuning binding；移除無條件 `dev_info()`。 |
| [`0004` PMI8998 Type-C](kernel-patches/0004-usb-typec-qcom-add-pmi8998-pd-sink.patch) | 有專用 compatible、resource table 與 binding。 | 由 PMI8998 原廠 register map 確認能否共用 `pm8150b_pdphy_res`；限定 SMB2 5–9 V init 不影響其他 SMB2。 |
| [`0013` haptics output stage](kernel-patches/0013-input-qcom-spmi-haptics-enable-output-stage.patch) | 原廠調用鏈與實機震動都證明 Razer PMI8998 需要 `HAP_EN_CTL3`。 | 以 PMIC subtype/version match-data 限定，或證明這是此驅動所支援硬體共有的初始化。 |
| [`0015` Slimbus fallback](kernel-patches/0015-slimbus-qcom-ngd-fallback-to-qmi-service.patch) | QMI server arrival 啟動 NGD 的方向符合原廠流程。 | 只對服務不存在類 PDR 錯誤 fallback，不可吞掉 `-ENOMEM` 等真正錯誤；驗證 QMI/PDR/SSR 競爭與重複啟動。 |
| [NT36830 面板驅動](panel-driver/panel-novatek-nt36830.c) | 專用驅動內保留 Razer 原廠初始化表是合理的。 | 移除過度寬鬆的 `novatek,nt36830`，只保留 `razer,aura-nt36830`，除非已證明其他 NT36830 面板完全相容。 |

### 作用域與主線抽象合理

- [`0005` charge behaviour](kernel-patches/0005-power-supply-qcom-smbx-add-charge-behaviour.patch)：
  使用標準 power-supply API，沒有 Razer 專屬 magic value。
- [`0006` S5K3H7 driver](kernel-patches/0006-media-i2c-add-s5k3h7.patch)：
  獨立 sensor driver 是正確作用域；仍待實機驗證 CCI 交易與 mode table。
- [`0007` haptics 電壓/電流](kernel-patches/0007-input-qcom-spmi-haptics-add-vmax-current-limit.patch)：
  有 binding、數值驗證與保持舊行為的預設值，Razer 數值由 DTS opt-in。
- [`0008` QUAT MI2S 多 codec](kernel-patches/0008-asoc-qcom-sdm845-configure-all-quat-mi2s-codecs.patch)：
  使用 ASoC 現有 `for_each_rtd_codec_dais()` 抽象，並正確傳遞錯誤。
- [`0009` haptics direct mode](kernel-patches/0009-input-qcom-spmi-haptics-support-factory-direct-mode.patch)：
  由 DTS 選擇且預設不改變舊行為。

[`0010` Q6ASM memory-map log](kernel-patches/0010-asoc-q6asm-log-memory-map-request.patch)
只是無條件診斷輸出，不是功能移植。它應移到 diagnostics patch、dynamic debug
或 tracepoint，不列入正式 production patch。

上述「作用域合理」不等於「硬體功能完成」。相機、音訊、震動與面板仍必須
分別以實機 log 證明 enumeration、command acceptance、data movement 與
physical output，才能更新上方硬體支援清單。

## 外部供電與充電策略

`razer-charge-limits.service` 初始會進入 `external-power` 模式。USB 輸入在線
且電池高於 40% 時，服務會選擇 `inhibit-charge`：USB 供電路徑維持開啟，
但不對電池充電。電量到達 40% 或以下時，服務會鎖存進入 `charge-cycle`、
切換成 `auto`，並持續充到 80% 才回到 `external-power`。狀態會寫入
`/var/lib/razer-charge-limits/state`，重新啟動服務或手機後仍會保留。

這個策略不會在硬體上切斷電池。電池仍可處理瞬間負載；如果接的是電流不足
的電腦 USB port，電池也可能同時補足系統用電。可用以下指令確認策略與電流
方向：

```bash
cat /sys/class/power_supply/pmi8998-charger/online
cat /sys/class/power_supply/pmi8998-charger/charge_behaviour
cat /sys/class/power_supply/qcom-battery/current_now
cat /var/lib/razer-charge-limits/state
```

## 實驗用控制面板

`experiments/razer-control-panel/` 內的 DRM/KMS 面板會分開顯示 RRADC 量到的
USB 輸入電壓、電流、功率與電池電流，也提供 WiFi 設定及暫時性的
`CHARGE TO 100%` 測試按鈕。程式會保留在 repository 供開發測試，但本機
建置與 GitHub Actions release 都不會安裝；部署方式請看它的
[README](experiments/razer-control-panel/README.md)。

推進紀錄放在 `doc/`。已驗證的 WebKitGTK/Epiphany + sway Home Assistant
kiosk prototype 封存在 `rootfs-scripts/kiosk-prototype/`；只有 `ha`
userspace profile 會安裝，預設映像不會安裝。

## Release Profiles

硬體 image profile 固定是 `base`。應用程式 stack 由
`RAZER_USERSPACE_PROFILE` 或 release tag suffix 決定：

- `v1.0.0` -> `none`：不預裝應用的硬體平台映像。
- `v1.0.0-ha` -> `ha`：Home Assistant kiosk 套件與 prototype。
- `v1.0.0-3dprinter` -> `3dprinter`：Klipper/Moonraker/HelixScreen stack。

## 建置

前置需求：

- Windows 11、WSL2 Ubuntu 24.04。
- 至少 30 GB 可用空間。
- Windows 端 Android Platform Tools。
- 已解鎖 bootloader 的 Razer Phone 2。
- Razer factory 包 `aura-p-release-3201-user-full.zip` 或其中的
  `modem.img`。專有 firmware 不放進 Git。

建立建置環境：

```powershell
git clone https://github.com/aa846301/razorphone2linux.git
cd razorphone2linux
wsl bash -lc "cd /mnt/c/repo/razorphone2linux && bash scripts/01-setup-environment.sh"
```

抽取 firmware：

```powershell
wsl bash -lc "cd /mnt/c/repo/razorphone2linux && bash scripts/extract-modem-firmware.sh"
```

建置預設不預裝應用的 native-panel 映像：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-all-wsl.ps1 all -NativePanel
```

本機建置可選 userspace profile：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-all-wsl.ps1 all -NativePanel -UserspaceProfile ha
powershell -ExecutionPolicy Bypass -File scripts\build-all-wsl.ps1 all -NativePanel -UserspaceProfile 3dprinter
```

完成品輸出到 `output/base/`。如果 kernel 與 rootfs modules release 不一致，
boot packager 會拒絕產生 `boot.img`。

## GitHub Actions

`Build flashable image` workflow 會在 push `master` 時建立預設分支共用快取，
並在 push `v*` tag 時發佈 release。GitHub Actions cache 會依 Git ref 隔離，
所以一個 release tag 建立的 cache 無法直接由下一個 tag 使用。推 release tag
前，應先讓相同 commit 的 `master` run 完成；tag run 才能從預設分支復用
kernel core、`ccache`、已抽取 firmware 與 rootfs cache。

`master` 暖 cache 時會同時使用三個獨立 ARM64 job：工廠 firmware 抽取、
kernel/DTB/modules，以及不依賴 kernel 的 rootfs base。rootfs base 只包含
distribution、套件、帳號與可選 application profile；release job 最後再由
`03-refresh-rootfs.sh` 套用當次 firmware、modules、services 與 initramfs。
因此 firmware 前置失敗時，不會連已成功完成的 kernel build 一起丟掉。
三個 seed job 全部成功後，正常的 `build` job 必須在 `master` 還原這些 cache，
並組裝一份完整驗證映像。只有 tag build 會把這條已驗證流程正式發佈成
GitHub Release。

YAML 會直接列出 GitHub `ubuntu-24.04-arm` hosted runner 上的 release
recipe：選 tag profile、匯入韌體、建 native-panel/GPU kernel、建 ARM64
rootfs、封裝 `boot.img`，並上傳只包含可刷入映像的 release zip：
`boot.img`、`rootfs-sparse.img` 與 `vbmeta_disabled.img`。`master` run 只會
上傳供驗證的 Actions artifact，不會建立 GitHub Release；只有 `v*` tag
會正式發佈。

請將 `RAZER_FACTORY_ZIP_URL` 設成 repository variable 或 secret，指向
`aura-p-release-3201-user-full.zip`。公開上游 URL 可以用 variable；私有
大檔 URL 則用 secret，若需要 HTTP auth header，再加
`RAZER_FACTORY_ZIP_AUTH_HEADER` secret。Tag 會自動選 profile：`v*`、`v*-ha`、
`v*-3dprinter`。

## 刷機

警告：刷入 userdata 會清除 Android 使用者資料。若尚未刷過 disabled
vbmeta，先執行一次：

```powershell
fastboot --disable-verity --disable-verification flash vbmeta output\base\vbmeta_disabled.img
```

平常刷機：

```powershell
fastboot flash boot_a output\base\boot.img && fastboot flash boot_b output\base\boot.img && fastboot flash userdata output\base\rootfs-sparse.img && fastboot reboot
```

預設帳密為 `klipper` / `klipper`，首次開機後請修改。

## 常用檢查

```bash
nmcli device
nmcli device wifi list
systemctl status razer-charge-limits razer-panel-idle-blank razer-wifi-ready
journalctl -b -u rmtfs -u tqftpserv -u razer-wifi-ready
```

操作細節請看 [FLASH-GUIDE.md](FLASH-GUIDE.md)、[RECOVERY.md](RECOVERY.md)
與 [doc/ci-and-release.md](doc/ci-and-release.md)。
