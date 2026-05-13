# Razer Phone 2 (aura) - 主線 Linux 移植

將主線 Linux 移植到 Razer Phone 2 (Qualcomm SDM845)，用作 HelixScreen 3D 列印觸控螢幕控制器。

## 最終目標

1. 🔄 通電自啟動 (4.2V 電池供電 + 保護板): 待 PMIC PON/ABL/硬體方案驗證
2. ✅ 開機自動啟動 HelixScreen: 實機已安裝 HelixScreen v0.99.57，`helixscreen.service` active，fbdev 後端進入 main loop
3. ✅ Linux 發行版: Ubuntu Noble 24.04 (ARM64) 已可開機登入
4. ⚠️ WiFi 驅動 (WCN3990 / ath10k_snoc): driver 已綁定 `18800000.wifi`，Razer 原機 `wlanmdsp.mbn`/`bdwlan.bin` 已抽取；目前 MSS remoteproc `4080000.remoteproc` fatal crash，尚未產生 `wlan0`
5. ✅ 觸控驅動 (Synaptics RMI4 DSX): 實機已枚舉 `Synaptics S3708AR` 到 `/dev/input/event0`
6. ✅ USB 驅動: USB ACM console + CDC NCM gadget 已可用，`usb0` 為 `UP LOWER_UP`；USB host/MCU 通訊仍待 Type-C role/host bring-up

## 硬體規格

| 組件 | 型號                                       | 主線驅動      |
|------|--------------------------------------------|---------------|
| SoC  | Qualcomm SDM845                            | ✅ 已支持      |
| 顯示 | NovaTeK NT36830, 1440×2560, Dual DSI + DSC | ⚡ 新驅動      |
| 觸控 | Synaptics RMI4 (I2C-7 @ 0x20)              | ✅ rmi_i2c     |
| WiFi | Qualcomm WCN3990                           | ✅ ath10k_snoc |
| USB  | DWC3 USB 3.1 Type-C                        | ✅ dwc3-qcom   |
| PMIC | PM8998 + PMI8998                           | ✅ qcom-rpmh   |
| 音頻 | WCD9340 (Slimbus)                          | ✅ qcom-sdm845 |
| 儲存 | UFS 2.1                                    | ✅ ufs-qcom    |

## 專案結構

```
razorphone2linux/
├── dts/
│   └── sdm845-razer-aura.dts      # 完整設備樹文件
├── panel-driver/
│   └── panel-novatek-nt36830.c     # NT36830 面板驅動 (Dual DSI + DSC)
├── scripts/
│   ├── 01-setup-environment.sh     # WSL 環境搭建 + 工具鏈安裝
│   ├── 02-build-kernel.sh          # 內核交叉編譯
│   ├── 03-build-rootfs.sh          # Ubuntu rootfs 製作 + 顯示環境
│   ├── 04-make-boot-image.sh       # boot.img 製作
│   └── 05-flash.sh                 # 刷機腳本
└── README.md
```

## 快速開始

### 前置條件

- Windows 10/11 + WSL2 (Ubuntu 24.04)
- Razer Phone 2 (已解鎖 bootloader)
- USB 線 (Type-C)
- Razer Phone 2 原廠 ROM (用於提取固件 blob)

### 構建步驟
WSL ubuntu sudo 密碼是klipper
所有步驟在 WSL Ubuntu 中執行：

```bash
# 1. 環境搭建 (安裝交叉編譯器、克隆內核源碼)
bash scripts/01-setup-environment.sh

# 2. 編譯內核 (含設備樹 + NT36830 面板驅動)
bash scripts/02-build-kernel.sh

# 3. 製作 rootfs (Ubuntu + 顯示環境 + 所有驅動)
sudo bash scripts/03-build-rootfs.sh

# 4. 製作 boot.img
bash scripts/04-make-boot-image.sh

# 5. 刷機
bash scripts/05-flash.sh
```

### 固件提取

在構建 rootfs 之前，需要從 Razer Phone 2 原廠 ROM 提取固件：

```bash
# 需要的固件文件 (放入 ~/razorphone2linux/firmware/)
firmware/
├── qcom/sdm845/Razer/aura/
│   ├── adsp.mbn        # Audio DSP
│   ├── cdsp.mbn        # Compute DSP
│   ├── a630_zap.mbn    # GPU shader
│   ├── venus.mbn       # Video codec
│   ├── mba.mbn         # Modem Boot Auth
│   ├── modem.mbn       # Modem firmware
│   ├── slpi.mbn        # Sensor Low Power Island
│   └── ipa_fws.mbn     # Internet Protocol Accelerator
├── ath10k/WCN3990/hw1.0/
│   ├── board.bin        # WiFi calibration data
│   └── firmware-5.bin   # WiFi firmware
└── qca/Razer/aura/
    └── crnv21.bin       # Bluetooth firmware
```

## 通電自啟動

Razer Phone 2 改裝為 4.2V 直供電源後，需要配置 PM8998 PMIC 的
Power-On (PON) 模塊使其在檢測到電源接入時自動開機。

---

## 開機除錯記錄與移植分析

### 目前狀態 (2026-04-17)

**症狀：** 刷入 `boot_a` 後，螢幕顯示 **8 個 Linux 企鵝圖案**（Tux），無閃爍光標，無任何文字輸出，系統無回應。

**診斷：**
- 8 隻企鵝 = kernel 已成功啟動，SDM845 的 8 核心 (4×Kryo 385 Gold + 4×Kryo 385 Silver) 全部偵測到
- framebuffer 正常運作（simple-framebuffer 使用 bootloader 保留的顯存）
- 系統在 **late_initcall 階段凍結**

### 根本原因分析

#### 1. 缺少 `clk_ignore_unused pd_ignore_unused` (已修正)

**這是最可能的凍結原因。** Qualcomm SoC 上的主線 Linux 會在 `late_initcall` 階段關閉它認為「未使用」的時鐘和電源域。但許多硬體（UFS 控制器、顯示器、USB）的時鐘實際上是 bootloader 開啟的，kernel 不知道它們正在使用中。

```
clk_ignore_unused  → 阻止 kernel 關閉「未使用」的時鐘
pd_ignore_unused   → 阻止 kernel 關閉「未使用」的電源域
```

**已修正：** 新的 cmdline:
```
console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0xA84000 clk_ignore_unused pd_ignore_unused root=/dev/disk/by-partlabel/userdata rootfstype=ext4 rootwait rw loglevel=7 pcie_aspm=off
```

#### 2. 設備樹 (DTS) 可能不完整

目前的 DTS 是參考 OnePlus 6 手寫的，**未從 Razer Phone 2 實機提取**。關鍵問題：

- **reserved-memory 地址可能錯誤** — 如果與 bootloader/TrustZone 保留的記憶體區域衝突，會導致 kernel panic
- **cont_splash_mem 地址/大小** — framebuffer 地址需與 ABL (Android Bootloader) 設定完全匹配
- **缺少某些必要的硬體節點** — regulators、clock 引用可能不對

**正確做法：** 從 Android 實機提取設備樹：
```bash
# 在 Android 系統上執行 (需 root)
adb shell cat /sys/firmware/fdt > android_dtb.bin

# 反編譯為 DTS
dtc -I dtb -O dts -o android_razer.dts android_dtb.bin
```
然後用 Linux 格式重寫（參考 OnePlus 6 的寫法）。

#### 3. initramfs 問題

目前使用的是最小化 busybox initramfs，可能的問題：
- 缺少 `devtmpfs` 的完整設備節點創建
- 沒有 `udev` 來建立 `/dev/disk/by-partlabel/` 符號連結
- UFS 設備可能需要更長的等待時間

**建議：** 使用 rootfs 對應系統（Ubuntu）生成的 initramfs，其中包含完整的 udev 和模組載入支援。

#### 4. root 設備路徑

建議使用 `root=LABEL=<分割標籤>` 或 `root=UUID=<UUID>`，而非硬編碼的設備路徑，這樣更可靠：
```
root=LABEL=rootfs
# 或
root=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 下一步行動計劃

#### Phase 1: 確認 kernel 能完整啟動（立即）
1. ✅ 加入 `clk_ignore_unused pd_ignore_unused` 到 cmdline
2. ✅ 改善 initramfs（加入更多除錯輸出、更長的 UFS 等待時間）
3. ✅ 修正 earlycon 為 `earlycon=msm_geni_serial,0xA84000`
4. 🔄 重新刷入測試

#### Phase 2: 提取 Android 設備樹（短期）
1. 下載 Razer Phone 2 線刷包（工廠映像）
2. 解包 boot.img 取得 Android DTB
3. 反編譯為 DTS 作為參考
4. 對比 reserved-memory、regulator、GPIO 等關鍵區段

#### Phase 3: 重寫 DTS（中期）
1. 以 OnePlus 6 (`sdm845-oneplus-common.dtsi`) 為基礎
2. 用 Android DTS 的 reserved-memory 和 regulator 數據替換
3. 修正面板、觸控、音頻等外設配置
4. 移除不需要的子系統（相機、NFC 等）

#### Phase 4: 使用 Ubuntu initramfs（中期）
1. 在 rootfs 構建時用 `update-initramfs` 生成完整 initramfs
2. 包含 UFS 驅動模組和 udev 規則
3. 支援 `root=LABEL=` 和 `root=UUID=`

### 參考資源

| 資源                                                                                                               | 用途                               |
|--------------------------------------------------------------------------------------------------------------------|------------------------------------|
| [OnePlus 6 mainline DTS](https://gitlab.com/sdm845-mainline/linux/-/tree/sdm845/6.16-dev/arch/arm64/boot/dts/qcom) | SDM845 DTS 寫法參考                |
| [Razer Phone 2 工廠映像](https://s3.amazonaws.com/cheryl-factory-images/aura-p-release-3201-user-full.zip)         | Android 9.0 MR6 線刷包             |
| [Razer Phone 2 Kernel Source](https://cheryl-factory-images.s3.amazonaws.com/msm-4.9-3225.tar)                     | Android kernel 原始碼 (含下游 DTS) |
| [postmarketOS Razer Phone 2](https://wiki.postmarketos.org/wiki/Razer_Phone_2_(razer-aura))                        | 社群移植參考                       |

### 線刷包內容說明

Razer Phone 2 使用 **A/B 分區方案**，工廠映像包含：

| 分區                         | 說明                          | A/B |
|------------------------------|-------------------------------|-----|
| `boot`                       | kernel + ramdisk (64MB)       | ✅   |
| `dtbo`                       | Device Tree Overlay (8MB)     | ✅   |
| `system`                     | Android 系統 (~3.5GB)         | ✅   |
| `vendor`                     | 廠商特定 HAL + firmware (1GB) | ✅   |
| `vbmeta`                     | AVB 驗證 metadata             | ✅   |
| `userdata`                   | 使用者資料 (~46.7GB)          | ❌   |
| `xbl`, `abl`, `tz`, `hyp` 等 | Bootloader 鏈                 | ✅   |

**重要：** 主線 Linux 不需要刷 `dtbo` 分區，因為 DTB 已 append 到 `Image.gz-dtb` 中。已清空 dtbo 是正確做法。

### 從 Android 提取設備樹的方法

#### 方法 A: 從運行中的 Android (需 USB 連接)
```bash
# 如果手機還能進 Android 且已 root
adb shell su -c "cat /sys/firmware/fdt" > android_fdt.dtb
dtc -I dtb -O dts -o android_razer_aura.dts android_fdt.dtb
```

#### 方法 B: 從工廠映像解包
```bash
# 1. 下載工廠映像
wget https://s3.amazonaws.com/cheryl-factory-images/aura-p-release-3201-user-full.zip

# 2. 解壓
unzip aura-p-release-3201-user-full.zip

# 3. 解包 boot.img (用 unpackbootimg)
unpackbootimg -i boot.img -o boot_unpacked/

# 4. 提取 DTB (可能 append 在 kernel image 後面)
#    或從 dtbo.img 中提取
python3 mkbootimg/mkdtboimg.py dump dtbo.img -b dtbo_entries/

# 5. 反編譯
dtc -I dtb -O dts -o android_razer.dts boot_unpacked/boot.img-dtb
```

#### 方法 C: 從 Android kernel source
```bash
# 下載 Razer Phone 2 kernel source (4.9 based)
wget https://cheryl-factory-images.s3.amazonaws.com/msm-4.9-3225.tar
tar xf msm-4.9-3225.tar

# DTS 通常在:
# arch/arm64/boot/dts/qcom/sdm845-*.dtsi
# 搜尋 "aura" 或 "cheryl2"
find . -name "*.dts*" | xargs grep -l "aura\|cheryl2"
```

### 串口除錯 (USB 網卡連接手機)

如果有 USB-C 轉 UART 線或 USB 網卡：
```bash
# 手機端 cmdline 已配置 console=ttyMSM0,115200n8
# 在電腦端用 minicom/screen 連接串口
screen /dev/ttyUSB0 115200

# 或透過 USB CDC ACM (g_serial gadget)
# 手機的 rootfs 已配置 ttyGS0 串口 getty
screen /dev/ttyACM0 115200
```

### 方案一：修改 ABL (Android Bootloader)

在 ABL 中跳過電源鍵等待邏輯，任何供電情況下直接啟動內核。

### 方案二：PMIC PON 寄存器配置

通過設備樹配置 PM8998 PON 模塊：

```dts
&pm8998_pon {
    /* Configure PON to auto-boot on power supply */
    qcom,warm-reset-poweroff-type = <0x04>; /* WARM_RESET_SHUTDOWN */
    qcom,hard-reset-poweroff-type = <0x07>; /* DVDD_HARD_RESET */
};
```

### 方案三：硬體短接

在電源按鍵的 PCB 連接處進行硬體修改，使電源鍵持續保持按壓狀態。
這是最簡單且最可靠的方案。

## 調試指南

### 串口調試

```bash
# 通過 USB serial gadget (需要從主機端連接)
screen /dev/ttyACM0 115200

# 通過 UART (需要焊接調試接口)
screen /dev/ttyUSB0 115200
```

### WiFi 配置

```bash
# 開機後使用 NetworkManager
nmtui          # TUI 介面
nmcli device wifi list
nmcli device wifi connect "SSID" password "PASSWORD"
```

### USB 與下位機通訊

```bash
# 連接 Klipper MCU 後應出現
ls /dev/ttyACM*

# 測試通訊
screen /dev/ttyACM0 250000
```

### 觸控校準

```bash
# 查看觸控設備
evtest
xinput list

# 校準觸控 (如果方向不對)
xinput set-prop "Synaptics RMI4" "Coordinate Transformation Matrix" 1 0 0 0 1 0 0 0 1
```

## 已知問題與注意事項

1. **NT36830 面板驅動**: DSI 初始化序列基於 Android 驅動推測，可能需要根據實際硬體調整
2. **Dual DSI + DSC**: 壓縮參數可能需要微調
3. **120Hz 支持**: 目前僅配置 60Hz 模式，120Hz 需要額外的 DSI 時鐘配置
4. **通電自啟動**: 需要根據實際情況選擇最適合的方案
5. **固件 blob**: 必須從原廠 ROM 提取，無法提供下載

## 參考資料

- [SDM845 主線 Linux 項目](https://gitlab.com/sdm845-mainline/linux)
- [OnePlus 6T 主線 DTS](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sdm845-oneplus-fajita.dts)
- [Razer Phone 2 Android 內核](https://github.com/ASKSAP/android_kernel_razer_aura)
- [LineageOS Razer Aura 設備配置](https://github.com/LineageOS/android_device_razer_aura)
- [PostmarketOS SDM845 Wiki](https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_845_(SDM845))
- [HelixScreen](https://github.com/prestonbrown/helixscreen)

## 授權

設備樹和面板驅動依照 GPL-2.0 授權。

# Wifi 
SSID: CimforceTw-Guest
Password: 61828630
