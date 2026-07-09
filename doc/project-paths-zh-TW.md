# Razer Phone 2 Linux 專案位置導覽

更新日期：2026-06-16

這份文件只整理「東西在哪裡」。目標是避免把正式來源、WSL build cache、暫存抽取物、舊測試輸出混在一起。

## 最重要的結論

| 類別 | Windows 路徑 | WSL 路徑 | 用途 |
|---|---|---|---|
| 專案根目錄 | `C:\repo\razorphone2linux` | `/mnt/c/repo/razorphone2linux` | 正式 repo。要改文件、DTS、config、scripts、firmware 都從這裡開始。 |
| WSL 工作區/cache | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux` | `/home/dinochang/razorphone2linux` | kernel source、rootfs raw image、build cache。不要把這裡當正式來源。 |
| 輸出產物 | `C:\repo\razorphone2linux\output` | `/mnt/c/repo/razorphone2linux/output` | boot.img、rootfs sparse、DTB、log/evidence。 |
| 文件 | `C:\repo\razorphone2linux\doc` | `/mnt/c/repo/razorphone2linux/doc` | 專案狀態、對照報告、測試結論。 |

如果在 WSL 裡找不到檔案，先記得 repo 不是 `/repo`，而是：

```bash
cd /mnt/c/repo/razorphone2linux
```

## 雷蛇原廠固件與原廠資料

### 原廠完整包

| 項目 | 路徑 | 說明 |
|---|---|---|
| 原廠 zip | `C:\repo\razorphone2linux\aura-p-release-3201-user-full.zip` | Razer Phone 2 factory package 原始壓縮檔。 |
| 解壓後原廠包 | `C:\repo\razorphone2linux\aura-p-release-3201-user-full\aura-p-release-3201` | 原廠 boot.img、dtbo.img、modem.img、dsp.img、vendor.img 等。 |
| 原廠 boot.img | `C:\repo\razorphone2linux\aura-p-release-3201-user-full\aura-p-release-3201\boot.img` | Android factory boot，內含原廠 kernel/DTB。 |
| 原廠 dtbo.img | `C:\repo\razorphone2linux\aura-p-release-3201-user-full\aura-p-release-3201\dtbo.img` | Android factory DTBO。 |
| 原廠 modem.img | `C:\repo\razorphone2linux\aura-p-release-3201-user-full\aura-p-release-3201\modem.img` | 權威 modem firmware 來源。 |
| 原廠 dsp.img | `C:\repo\razorphone2linux\aura-p-release-3201-user-full\aura-p-release-3201\dsp.img` | ADSP/CDSP/SLPI 等參考來源之一。 |

### 從原廠抽出的 Android DTS/DTB

| 項目 | 路徑 | 說明 |
|---|---|---|
| 原廠 boot base DTB/DTS | `C:\repo\razorphone2linux\android-fdt\android-base-00.dtb` / `android-base-00.dts` | 從 Razer factory boot.img 抽出的 base DT。查 reserved-memory、mss、mdss、power/reset 時常用。 |
| 原廠 DTBO entries | `C:\repo\razorphone2linux\android-fdt\dtbo-entry-00.dts` 到 `dtbo-entry-05.dts` | 從 Razer factory dtbo.img 抽出的 overlays。 |
| factory DT 對照報告 | `C:\repo\razorphone2linux\doc\razer-factory-dtbo-mss-wlan-compare-2026-06-08.md` | Razer factory DTB/DTBO 與 mainline 移植 DTS 的 MSS/WLAN 對照。 |
| factory power/reset audit | `C:\repo\razorphone2linux\doc\factory-mss-mdss-power-reset-audit-2026-06-09.md` | MSS/MDSS power/reset 相關整理。 |

## 正式移植後的 DTS / Kernel Config

| 項目 | 路徑 | 說明 |
|---|---|---|
| Razer 移植 DTS 正式來源 | `C:\repo\razorphone2linux\dts\sdm845-razer-aura.dts` | 這是 repo 控制的 DTS。改 Razer DTS 應該改這裡。 |
| build 時 kernel source 內 DTS | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux\kernel\linux\arch\arm64\boot\dts\qcom\sdm845-razer-aura.dts` | build 腳本會同步 repo DTS 到這裡。不要只手改這裡，否則下次 build 可能被覆蓋。 |
| kernel config fragment | `C:\repo\razorphone2linux\config\razer-aura.config` | 正式 kernel config 改這裡，不要只改 WSL kernel `.config`。 |
| kernel patches | `C:\repo\razorphone2linux\kernel-patches` | q6v5/MSS/QRTR/PDM 等 kernel instrumentation 正式 patch 放這裡。 |
| rejected patches | `C:\repo\razorphone2linux\kernel-patches\rejected` | 已測過但不採用的 patch，保留作證據。 |

## 打包進 rootfs 的韌體

正式 rootfs refresh/build 會使用 repo 裡的 `firmware/`，不是 `.tmp/`。

| 類別 | 路徑 | 內容 |
|---|---|---|
| Razer SDM845 firmware | `C:\repo\razorphone2linux\firmware\qcom\sdm845\Razer\aura` | `mba.mbn`、`modem.mbn`、`modem.b*`、`wlanmdsp.mbn`、`adsp/cdsp/slpi/venus`、`modemr.jsn`、`modemuw.jsn`。 |
| WCN3990 ath10k firmware | `C:\repo\razorphone2linux\firmware\ath10k\WCN3990\hw1.0` | `firmware-5.bin`、`board.bin`、`board-2.bin`、`bdwlan*`。 |
| modem firmware 抽取腳本 | `C:\repo\razorphone2linux\scripts\extract-modem-firmware.sh` | 從原廠 `modem.img` 抽 `modem/adsp/cdsp/slpi/venus/mba/wlanmdsp` 到正式 firmware 目錄。 |

常用查找：

```bash
find /mnt/c/repo/razorphone2linux/firmware/qcom/sdm845/Razer/aura -maxdepth 1 -type f | sort
find /mnt/c/repo/razorphone2linux/firmware/ath10k/WCN3990/hw1.0 -maxdepth 1 -type f | sort
```

刷進 rootfs 後，手機上主要會在：

```text
/usr/lib/firmware/qcom/sdm845/Razer/aura
/lib/firmware/qcom/sdm845/Razer/aura
/lib/firmware/image
/readonly/firmware/image
/usr/lib/firmware/ath10k/WCN3990/hw1.0
```

`/lib/firmware/image` 和 `/readonly/firmware/image` 主要是給 `tqftpserv`/Qualcomm 韌體查找相容用的 alias。

## OnePlus 6 參考資料

### OnePlus Android fastboot 包

| 項目 | 路徑 | 說明 |
|---|---|---|
| OnePlus 6 fastboot zip | `C:\repo\razorphone2linux\11.1.2.2-OP6-FASTBOOT.zip` | 使用者提供的 OnePlus 6 Android 參考包。 |
| 解包輸出 | `C:\repo\razorphone2linux\output\op6-android-11.1.2.2` | 解出的 `boot.img`、`dtbo.img`、DTB/DTS、grep 報告。 |
| OnePlus boot DTB/DTS | `C:\repo\razorphone2linux\output\op6-android-11.1.2.2\boot-dtbs` | 從 OnePlus boot.img 抽出的 DTB/DTS。 |
| OnePlus DTBO entries | `C:\repo\razorphone2linux\output\op6-android-11.1.2.2\dtbo-entries` | 從 OnePlus dtbo.img 抽出的 entries。 |
| OnePlus rmtfs/reserved grep | `C:\repo\razorphone2linux\output\op6-android-11.1.2.2\rmtfs-reserved-grep.txt` | OnePlus Android DTS 裡 rmtfs/reserved-memory 相關 grep 結果。 |
| OnePlus Android 對照文件 | `C:\repo\razorphone2linux\doc\op6-android-rmtfs-dtb-comparison-2026-06-10.md` | OnePlus Android 與 Razer 的 rmtfs/DTB 對照。 |

### OnePlus / upstream mainline DTS 參考

| 項目 | 路徑 | 說明 |
|---|---|---|
| OnePlus mainline common DTSI | `C:\repo\razorphone2linux\doc\sdm845-oneplus-common.dtsi` | Linux mainline OnePlus 6 common DTSI 參考。 |
| Xiaomi/Poco mainline DTSI | `C:\repo\razorphone2linux\doc\sdm845-xiaomi-beryllium-common.dtsi` | Poco F1/beryllium 參考。 |
| Samsung SDM845 DTS | `C:\repo\razorphone2linux\doc\sdm845-samsung-starqltechn.dts` | Samsung SDM845 參考。 |
| SDM845 SoC DTSI | `C:\repo\razorphone2linux\doc\sdm845.dtsi` | SDM845 SoC 層 DTSI 參考。 |

## postmarketOS / 參考 image 對照資料

| 項目 | 路徑 | 說明 |
|---|---|---|
| pmOS 參考抽取資料 | `C:\repo\razorphone2linux\output\pmos-oneplus-reference` | OnePlus/pmOS image 內 firmware layout、services、modules 等抽取結果。 |
| pmOS reference 文檔 | `C:\repo\razorphone2linux\doc\sdm845-reference-image-comparison-2026-05-29.md` | 參考 image 對照總結。 |
| pmOS / OnePlus 對照文檔 | `C:\repo\razorphone2linux\doc\pmos-oneplus-and-contrast-2026-06-02.md` | pmOS OnePlus 與 Razer contrast 筆記。 |
| postmarketOS SDM845 WiFi wiki 整理 | `C:\repo\razorphone2linux\doc\postmarketos-sdm845-wifi-reference-2026-06-02.md` | 使用者貼回的 wiki/MR 內容與本案適用性整理。 |

## WSL 裡的 build / cache / source

這裡是工作區，不是正式 source of truth。

| 類別 | WSL 路徑 | Windows UNC 路徑 | 說明 |
|---|---|---|---|
| WSL 工作根 | `/home/dinochang/razorphone2linux` | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux` | build/cache 總目錄。 |
| mainline kernel source | `/home/dinochang/razorphone2linux/kernel/linux` | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux\kernel\linux` | 由 build 腳本使用的 kernel source。不要只改這裡。 |
| pmOS contrast kernel source | `/home/dinochang/razorphone2linux/kernel/pmos-sdm845` | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux\kernel\pmos-sdm845` | postmarketOS SDM845 contrast kernel source。 |
| rootfs raw image/cache | `/home/dinochang/razorphone2linux/rootfs` | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux\rootfs` | raw rootfs、mount points、refresh mount。 |
| module install staging | `/home/dinochang/razorphone2linux/output/modules_install` | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux\output\modules_install` | kernel modules staging。 |
| mkbootimg tool | `/home/dinochang/razorphone2linux/mkbootimg-tool` | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux\mkbootimg-tool` | boot.img 打包工具。 |
| tqftpserv source/build | `/home/dinochang/razorphone2linux/tqftpserv` | `\\wsl.localhost\Ubuntu\home\dinochang\razorphone2linux\tqftpserv` | tqftpserv 編譯工作區。 |

原則：

- 要保留的修改：放回 `C:\repo\razorphone2linux`。
- kernel 改動：做成 `kernel-patches/*.patch`。
- DTS 改動：改 `dts/sdm845-razer-aura.dts`。
- config 改動：改 `config/razer-aura.config`。
- 不要只改 `/home/dinochang/razorphone2linux/kernel/linux` 裡的檔案，因為下次同步/重建可能消失。

## Build / Flash 產物在哪裡

| 產物 | 路徑 | 說明 |
|---|---|---|
| 最新 boot.img | `C:\repo\razorphone2linux\output\boot.img` | `scripts/build-all.sh validate-boot` 或 `validate` 產生。 |
| 最新 sparse rootfs | `C:\repo\razorphone2linux\output\rootfs-sparse.img` | 刷 userdata/rootfs 用。 |
| 最新 Image.gz | `C:\repo\razorphone2linux\output\Image.gz` | kernel image。 |
| 最新 DTB | `C:\repo\razorphone2linux\output\sdm845-razer-aura.dtb` | build 後 DTB。 |
| 最新 Image.gz-dtb | `C:\repo\razorphone2linux\output\Image.gz-dtb` | kernel + DTB 合併。 |
| kernel release | `C:\repo\razorphone2linux\output\kernel.release` | 判斷 modules 是否匹配。 |
| rootfs kernel release | `C:\repo\razorphone2linux\output\rootfs.kernel-release` | rootfs modules 版本紀錄。 |

### 刷回 Android 前保留的 Linux 可用 IMG

| 項目 | 路徑 | 說明 |
|---|---|---|
| 2026-06-16 Android restore 前 Linux 備份 | `C:\repo\razorphone2linux\output\linux-usable-image-backup-20260616-android-restore` | 刷回 Android 前保存的可回復 Linux `boot.img`、`rootfs-sparse.img`、DTB、kernel release、initramfs 與 SHA256。 |
| 備份說明 | `C:\repo\razorphone2linux\output\linux-usable-image-backup-20260616-android-restore\README.md` | 內含 Linux 復原 fastboot 指令。 |
| 備份雜湊 | `C:\repo\razorphone2linux\output\linux-usable-image-backup-20260616-android-restore\SHA256SUMS.txt` | 備份檔案 SHA256，用來確認沒有複製中斷或檔案損壞。 |

命令：

```bash
cd /mnt/c/repo/razorphone2linux
bash scripts/build-all.sh validate-boot   # DTS/boot-only
bash scripts/build-all.sh validate        # kernel + refresh rootfs + boot
```

## 手機 live 測試與 evidence 輸出

| 類別 | 路徑 | 說明 |
|---|---|---|
| MSS crash evidence | `C:\repo\razorphone2linux\output\mss-crash-evidence-*` | `phone-mss-crash-evidence.sh` 或相關測試拉回的 log。 |
| rmtfs detail evidence | `C:\repo\razorphone2linux\output\rmtfs-detail-evidence-20260616-1143` | 目前最重要的 RFS 詳細讀取證據。 |
| full peripherals 測試 | `C:\repo\razorphone2linux\output\full-peripherals-mss-evidence-20260616` | slim/audio/bt/ipa/wifi 全開仍 MSS fatal 的證據。 |
| FS1/FS2 swap 舊測試 | `C:\repo\razorphone2linux\output\rmtfs-fs12-swap-evidence-20260602` | 舊 kernel 下 FS1/FS2 swap 測試紀錄。 |
| devcoredump 結果 | `C:\repo\razorphone2linux\output\mpss-coredump-20260615.elf` | remoteproc devcoredump，已知 payload 全 0。 |
| reserved-memory 對照 | `C:\repo\razorphone2linux\output\reserved-memory-compare` | live/factory/mainline reserved-memory 對照輸出。 |

`output/` 裡有很多一次性測試結果。判斷是否可信時，優先找同目錄下的 `README.md`、`session.txt`、`sha256.txt`、`dmesg-*.txt`、`qrtr-*.txt`。

## Rootfs 內會被安裝的設定

| 項目 | 路徑 | 說明 |
|---|---|---|
| runtime config | `C:\repo\razorphone2linux\rootfs-scripts\apply-runtime-config.sh` | rootfs refresh/build 時套用服務、firmware symlink、modules-load、blacklist、Helix 等設定。 |
| USB gadget setup | `C:\repo\razorphone2linux\rootfs-scripts\usb-gadget-setup.sh` | 手機 USB 網路/SSH 相關設定。 |
| final target installer | `C:\repo\razorphone2linux\rootfs-scripts\install-final-target.sh` | final target / userspace 安裝流程。 |
| rootfs ARM64 packages | `C:\repo\razorphone2linux\rootfs-packages\arm64` | repo 控制的 ARM64 `.deb`/package 輸入。 |
| rootfs binaries | `C:\repo\razorphone2linux\rootfs-binaries` | 放進 rootfs 的額外 binary。 |

## 腳本位置

| 腳本 | 路徑 | 用途 |
|---|---|---|
| build all entrypoint | `C:\repo\razorphone2linux\scripts\build-all.sh` | 主要 build 入口。 |
| build kernel | `C:\repo\razorphone2linux\scripts\02-build-kernel.sh` | 編 kernel/DTB/modules。 |
| refresh rootfs | `C:\repo\razorphone2linux\scripts\03-refresh-rootfs.sh` | 更新現有 rootfs。 |
| full rootfs build | `C:\repo\razorphone2linux\scripts\03-build-rootfs.sh` | 重建完整 rootfs。 |
| make boot image | `C:\repo\razorphone2linux\scripts\04-make-boot-image.sh` | 打包 boot.img。 |
| live module deploy | `C:\repo\razorphone2linux\scripts\deploy-live-module.ps1` | Windows 端部署 matching `.ko` 到手機。 |
| MSS crash evidence | `C:\repo\razorphone2linux\scripts\phone-mss-crash-evidence.sh` | 手機端收 MSS crash bundle。 |
| diag-router live build | `C:\repo\razorphone2linux\scripts\build-diag-router-live.sh` | live-only diag-router 測試用。 |
| userspace pd-mapper live build | `C:\repo\razorphone2linux\scripts\build-pdmapper-live.sh` | live-only pd-mapper contrast 測試用。 |

`deprecated-scripts/` 是舊腳本參考區。除非先整理回正式流程，不要直接跑。

## 常用找檔命令

### 找 Razer modem firmware

```bash
find /mnt/c/repo/razorphone2linux/firmware/qcom/sdm845/Razer/aura \
  -maxdepth 1 -name "modem*" -print | sort
```

### 找 WCN3990/ath10k firmware

```bash
find /mnt/c/repo/razorphone2linux/firmware/ath10k/WCN3990/hw1.0 \
  -maxdepth 1 -type f -print | sort
```

### 找 Razer 原廠 DTS 內容

```bash
rg -n "remoteproc@4080000|18800000.wifi|reserved-memory|rmtfs|mpss|wlan" \
  /mnt/c/repo/razorphone2linux/android-fdt/*.dts
```

### 找目前移植 DTS 內容

```bash
rg -n "mss|wifi|ipa|reserved-memory|rmtfs|glink|smp2p" \
  /mnt/c/repo/razorphone2linux/dts/sdm845-razer-aura.dts
```

### 找 OnePlus Android DTS 內容

```bash
rg -n "remoteproc|wifi|reserved-memory|rmtfs|mpss|wlan" \
  /mnt/c/repo/razorphone2linux/output/op6-android-11.1.2.2
```

### 找 OnePlus mainline DTS 內容

```bash
rg -n "mss|wifi|ipa|reserved-memory|rmtfs|glink|smp2p" \
  /mnt/c/repo/razorphone2linux/doc/sdm845-oneplus-common.dtsi
```

### 找目前測試 log

```bash
find /mnt/c/repo/razorphone2linux/output -maxdepth 2 \
  \( -name "README.md" -o -name "session.txt" -o -name "dmesg*.txt" -o -name "qrtr*.txt" \) \
  | sort
```

## 容易混淆的目錄

| 目錄 | 判斷 |
|---|---|
| `C:\repo\razorphone2linux\.tmp` | 暫存抽取/比對。不要把它當正式來源。 |
| `C:\repo\razorphone2linux\output` | 產物與 evidence。可讀、可引用，但通常不是 source of truth。 |
| `/home/dinochang/razorphone2linux/kernel/linux` | WSL 內 build 用 kernel tree。不要只改這裡。 |
| `C:\repo\razorphone2linux\deprecated-scripts` | 舊腳本。不要直接用來取代正式 build flow。 |
| `C:\repo\razorphone2linux\android-fdt` | Razer 原廠 DTB/DTS 抽取結果，可用來對照，不是移植 DTS 正式來源。 |

## 判斷「我要改哪裡」

| 你想做的事 | 應該改哪裡 |
|---|---|
| 改 Razer DTS | `dts/sdm845-razer-aura.dts` |
| 改 kernel config | `config/razer-aura.config` |
| 加 kernel instrumentation | `kernel-patches/*.patch` |
| 換/補 Razer modem firmware | `firmware/qcom/sdm845/Razer/aura` |
| 換/補 WCN3990 board/firmware | `firmware/ath10k/WCN3990/hw1.0` |
| 改 rootfs 啟動服務/firmware symlink | `rootfs-scripts/apply-runtime-config.sh` |
| 改 build 流程 | `scripts/*.sh`，優先從 `scripts/build-all.sh` 入口看 |
| 查原廠 Razer DTS 寫法 | `android-fdt/*.dts` |
| 查 OnePlus Android 寫法 | `output/op6-android-11.1.2.2/**/*.dts` |
| 查 OnePlus mainline 寫法 | `doc/sdm845-oneplus-common.dtsi` |

## 一句話記憶

- 正式 repo：`C:\repo\razorphone2linux`
- WSL repo 路徑：`/mnt/c/repo/razorphone2linux`
- WSL build cache：`/home/dinochang/razorphone2linux`
- Razer 原廠包：`aura-p-release-3201-user-full\aura-p-release-3201`
- Razer 原廠 DTS：`android-fdt`
- Razer 移植 DTS：`dts\sdm845-razer-aura.dts`
- Razer 韌體打包來源：`firmware\qcom\sdm845\Razer\aura`
- WCN3990 韌體打包來源：`firmware\ath10k\WCN3990\hw1.0`
- OnePlus Android DTS：`output\op6-android-11.1.2.2`
- OnePlus mainline DTS：`doc\sdm845-oneplus-common.dtsi`
