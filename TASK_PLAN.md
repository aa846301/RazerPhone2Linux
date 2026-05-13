# Razer Phone 2 主線 Linux 移植 Task Plan

本文把 Razer Phone 2 (`aura`, SDM845) 移植到主線 Linux 的工作拆成可執行任務。原則是先建立可觀測、可回滾的最小閉環，再逐步把板級設備樹、內核、rootfs、固件與使用者空間補完整。每一階段都必須產生可檢查的檔案或實機證據。

## 0. 目前基線

- Windows 上已有 WSL2 Ubuntu，可用於交叉編譯和 rootfs 製作。
- 裝置已能啟動 Ubuntu 24.04.4 LTS，核心版本為 `6.16.0-rc2-ged6098a37a4c-dirty`，可透過 USB gadget serial `ttyGS0` 登入。
- USB ACM console 已經可用；CDC NCM 網路 gadget 腳本已部署到 `/usr/local/bin/usb-gadget-setup.sh`。
- `post-internet-setup.sh` 已修正為 sudo 部署，並改為 HelixScreen 終局；`--helix` / `--helixscreen` 可用，`--klipperscreen` 保留為舊命令相容別名。
- 實機已透過 USB NCM + SSH reverse proxy 完成套件安裝；`klipper.service`、`moonraker.service`、`helixscreen.service` 都是 active。
- HelixScreen v0.99.57 已安裝在 `/home/klipper/helixscreen`，fbdev 後端已啟動，journal 顯示 `UI created successfully` 和 `Entering main loop`。
- 觸控已枚舉為 `Synaptics S3708AR`，事件節點為 `/dev/input/event0`。
- WiFi 仍未完成：`ath10k_snoc` 已綁定 `18800000.wifi`，但尚未產生 `wlan0`；目前阻塞點是 MSS remoteproc `4080000.remoteproc` 進入 `fatal error` / `crashed`。
- 工作區已有主線 DTS 初版：`dts/sdm845-razer-aura.dts`，並已有 Android FDT/DTBO 反編譯資料在 `android-fdt/`。

## 1. 工具鏈與工作區固定

目標：確保每次 build 都從同一套輸入產生可追蹤輸出。

1. 確認 WSL 發行版：`wsl -l -v` 應顯示 Ubuntu / WSL2。
2. 在 WSL 中安裝編譯依賴：`bc`, `bison`, `flex`, `gcc-aarch64-linux-gnu`, `make`, `dtc`, `debootstrap`, `qemu-user-static`, `android-sdk-libsparse-utils`, `android-tools-mkbootimg`, `android-tools-fastboot`, `rsync`, `zerofree`。
3. 固定 Linux source 位置為 `~/razorphone2linux/kernel/linux`，工作區原始檔從 `/mnt/c/repo/razorphone2linux` 複製進 kernel tree。
4. 每次 build 後保存：
   - `output/Image.gz`
   - `output/sdm845-razer-aura.dtb`
   - `output/Image.gz-dtb`
   - `output/modules_install/`
   - `output/build.log`
   - 對應 `.config` 或 `kernelrelease`
5. 驗證：`bash -n scripts/*.sh wsl-scripts/*.sh` 無語法錯誤，`dtc` 能反編譯生成的 DTB。

## 2. Android 板級資料萃取

目標：不靠猜測寫板級 DTS，而是把 Android 下游資料轉成主線可用的描述。

1. 從工廠映像與已解包資料整理三類來源：
   - `android-fdt/android-base-00.dts`
   - `android-fdt/dtbo-entry-*.dts`
   - Razer Android kernel source 內的 `aura` / `cheryl2` / `RC2_common` DTSI。
2. 建立對照表，逐項記錄下游名稱、GPIO、regulator、主線節點與目前 DTS 行號：
   - reserved memory：`rmtfs`, `cont_splash`, modem/adsp/cdsp/slpi/venus/ipa memory
   - display：NT36830 panel, reset GPIO 6, TE GPIO 10, mode GPIO 52, power entries
   - touch：Synaptics RMI4, I2C bus, address, IRQ GPIO 31, reset GPIO 32, power GPIO
   - USB：DWC3 mode, Type-C/PMIC/PHY routing, HS/SS PHY supplies
   - WiFi/BT：WCN3990 supplies, firmware/calibration variant, UART6 BT
   - UFS：reset GPIO 150 and supply rails
   - power keys / volume keys / PON / charger / fuel gauge
3. 驗證：每個寫進主線 DTS 的 GPIO 和 regulator 都能追到 Android FDT 或同 SoC 主線板子的寫法。

## 3. DTS 主線化

目標：產出一份可以長期維護的 `sdm845-razer-aura.dts`，不是只靠 build script 臨時覆寫。

1. 保留 debug-safe USB 策略作為目前預設：
   - `dr_mode = "peripheral"`
   - `maximum-speed = "high-speed"`
   - 只綁定 `usb_1_hsphy`
   - `usb_1_qmpphy` 暫時 disabled
2. 對齊 Android reserved memory：
   - 保留已確認的 `cont_splash_mem` / simple framebuffer `0x9d400000`
   - 校正 `rmtfs_mem`
   - 補齊 remoteproc 需要且下游明確存在的 carveout
3. 完成電源樹：
   - `apps_rsc` 的 PM8998 / PMI8998 / PM8005 regulator 來源與電壓必須對齊下游資料。
   - 面板 rail 要覆蓋 Android `qcom,panel-supply-entries` 中的每一條供電。
   - 觸控 rail 要覆蓋 VDD、VIO、reset、interrupt。
4. 完成外設節點：
   - UFS、USB、WiFi/BT、touch、display、WLED、charger、fuel gauge、buttons。
   - 相機、NFC、haptics、audio amp 可以後置，但資料要整理進對照表，避免日後重複猜測。
5. 驗證：
   - `make dtbs` 成功。
   - `dtc -I dtb -O dts output/sdm845-razer-aura.dtb` 可反編譯。
   - 實機 `dmesg` 中沒有 regulator lookup、GPIO request、reserved memory overlap 的致命錯誤。

## 4. Kernel 編譯與配置

目標：讓核心支援啟動、儲存、USB console、WiFi、觸控、顯示與 Klipper MCU 通訊。

1. 以 SDM845 主線分支或接近 upstream 的 6.16 系列為基礎。
2. 導入：
   - `dts/sdm845-razer-aura.dts`
   - `panel-driver/panel-novatek-nt36830.c`
   - Kconfig / Makefile entry
3. 關鍵 config：
   - UFS：`SCSI_UFS_QCOM`
   - USB gadget：`USB_DWC3_QCOM`, `USB_CONFIGFS`, `USB_CONFIGFS_ACM`, `USB_CONFIGFS_NCM`, `USB_ACM`
   - WiFi：`ATH10K_SNOC`, `QCOM_Q6V5_WCSS`, `QCOM_WCNSS_PIL`, `QRTR`
   - touch：`RMI4_CORE`, `RMI4_I2C`, `RMI4_F01`, `RMI4_F12`
   - display：`DRM_SIMPLEDRM`, `DRM_MSM`, `DRM_PANEL_NOVATEK_NT36830`
   - debug：`PSTORE`, `PSTORE_RAM`, `SERIAL_MSM_CONSOLE`
4. 產出 `Image.gz`, `dtb`, `modules_install`。
5. 驗證：
   - WiFi 模組存在：`ath10k_core.ko`, `ath10k_snoc.ko`, `qcom_q6v5_wcss.ko`
   - USB NCM 所需 config 存在：`CONFIG_USB_CONFIGFS_NCM=y/m`
   - 實機可進入 login prompt。

## 5. Rootfs 製作

目標：Debian/Ubuntu ARM64 rootfs 可直接啟動 systemd，並可支援列印控制器工作流。

1. 建立 ext4 image，label 設為 `rootfs`。
2. 使用 `debootstrap --arch arm64 noble` 建 Ubuntu 24.04 rootfs；若改 Debian，使用 bookworm/trixie 並同步調整 sources。
3. 啟用：
   - NetworkManager
   - SSH
   - `serial-getty@ttyMSM0`
   - `serial-getty@ttyGS0`
   - `usb-gadget.service`
   - `resizefs.service`
4. 安裝：
   - `rmtfs`, `qrtr-tools`, `linux-firmware`, `kmod`, `udev`
   - HelixScreen 依賴與 fbdev 顯示後端需要的 runtime packages
5. 複製：
   - kernel modules 到 `/lib/modules/<kernelrelease>`
   - firmware 到 `/usr/lib/firmware/`
   - WCN3990 ath10k firmware 到 `/usr/lib/firmware/ath10k/WCN3990/hw1.0/`
6. 生成 initramfs，保存到 `output/initrd.img`。
7. 轉成 Android sparse image：`rootfs-sparse.img`。
8. 驗證：
   - chroot 中 `depmod -a` 成功
   - `/usr/lib/systemd/systemd` 是 ARM64 ELF
   - `/lib/modules/<kernelrelease>` 與正在啟動的 kernel release 一致
   - 首次開機後能自動 resize。

## 6. Boot image 與刷機

目標：在不依賴 Android userspace 的情況下穩定啟動主線 Linux。

1. 拼接 `Image.gz-dtb`。
2. 使用 busybox initramfs 作為早期掛載器，處理 UFS module、devtmpfs、rootfs switch。
3. cmdline 固定包含：
   - `earlycon=msm_geni_serial,0xA84000`
   - `console=ttyMSM0,115200n8`
   - `console=ttyGS0,115200`
   - `clk_ignore_unused pd_ignore_unused`
   - `fw_devlink=permissive`
   - `root=/dev/disk/by-partlabel/userdata rootfstype=ext4 rootwait rw`
4. 生成 disabled vbmeta。
5. 刷入：
   - `fastboot flash boot boot.img`
   - `fastboot flash userdata rootfs-sparse.img`
   - `fastboot flash vbmeta vbmeta_disabled.img`
6. 驗證：
   - Windows 出現 USB serial COM port。
   - 登入後 `uname -a` 符合新 build。
   - `findmnt /` 指向 userdata/rootfs。

## 7. USB 與下位機通訊

目標：同一顆 Type-C port 在 bring-up 期先當 peripheral debug，最終能與 Klipper MCU 通訊。

1. bring-up 期：
   - configfs gadget 建 ACM serial + NCM ethernet。
   - Windows 透過 ICS 分享網路給手機。
2. 驗證 NCM：
   - Windows 看到 CDC NCM / Remote NDIS 網卡。
   - 手機上 `ip link` 看到 `usb0`。
   - 手機能 ping 外網。
3. 最終 Klipper MCU：
   - 若 Razer Phone 2 需要作 USB host，必須補 Type-C/role-switch/PMIC 路徑，將 DTS 從 fixed peripheral 演進到可控 OTG/host。
   - 驗證插入 MCU 後出現 `/dev/ttyACM*` 或對應 USB serial device。
   - Klipper `mcu` 設定使用穩定 symlink，例如 `/dev/serial/by-id/...`。

## 8. WiFi bring-up

目標：WCN3990 在主線 `ath10k_snoc` 下工作。

1. 確認固件：
   - `/usr/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin`
   - `board.bin` 或 `board-2.bin`
   - `/usr/lib/firmware/qcom/sdm845/Razer/aura/mba.mbn`
   - `/usr/lib/firmware/qcom/sdm845/Razer/aura/modem.mbn`
2. 啟動 `rmtfs` 與 QRTR 相關服務。
3. 載入模組：`qcom_wcnss_pil`, `qcom_q6v5_wcss`, `ath10k_snoc`。
4. 檢查 `dmesg`：
   - firmware loaded
   - calibration variant accepted
   - wlan interface registered
5. 使用 NetworkManager 連線指定 SSID。
6. 驗證：
   - `nmcli device status` 有 `wifi`
   - `ip addr show wlan0`
   - 可 ping gateway 與外網。

## 9. 觸控 bring-up

目標：Synaptics RMI4 觸控能輸出 evdev 事件並被 HelixScreen 使用。

1. DTS 確認：
   - I2C bus 為 `i2c14`
   - address `0x20`
   - IRQ GPIO 31 active-low level
   - reset GPIO 32
   - VDD/VIO supply 正確
2. Kernel config 確認 RMI4 I2C 與 F01/F12。
3. 實機檢查：
   - `dmesg | grep -i rmi`
   - `ls /dev/input/event*`
   - `evtest`
4. X11/libinput 檢查：
   - `xinput list`
   - 必要時設定座標轉換矩陣。
5. 驗證：HelixScreen 上點擊、滑動、長按都可用。

## 10. 顯示與 HelixScreen

目標：先用 simpledrm/fbdev 保持畫面，後續再把 NT36830 DRM panel 做完整。

1. 啟動期保留 simple framebuffer，避免 panel driver probe 失敗造成不可觀測黑屏。
2. HelixScreen 第一版使用 fbdev 後端，目標解析度為 1440x2560 portrait。
3. NT36830 panel driver 後續要補齊：
   - Android DSI init command sequence
   - DSC 參數
   - dual DSI attach / detach
   - reset/power timing
   - 60/120 Hz mode table
4. 驗證：
   - `/dev/fb0` 存在。
   - `systemctl status helixscreen` 正常。
   - 螢幕顯示 HelixScreen。
   - 觸控事件能控制 UI。

## 11. 通電自啟動

目標：4.2V 電池保護板供電後，不按電源鍵即可啟動。

1. 軟體側優先檢查 PMIC PON/resin/power-key 行為：
   - DTS 啟用 PM8998 PON/RESIN 節點。
   - 檢查 Linux poweroff/reboot 行為是否保持可恢復。
2. Bootloader 側評估：
   - ABL 是否在插入 VBAT/USB 時等待按鍵。
   - 若需要修改 ABL，必須先完整備份分區，並保留 EDL/fastboot 恢復路徑。
3. 硬體側方案：
   - 若 PMIC/ABL 不能可靠達成，將 power key 以受控電路拉低一段時間，而不是永久短接。
   - 電源上升時序要滿足 PMIC power-key debounce。
4. 驗證：
   - 完全斷電 30 秒後重新上電，裝置自動進入 Linux。
   - 連續 20 次 power-cycle 沒有卡 bootloader 或 recovery。
   - rootfs 不因突然斷電損壞，必要時把系統改成只讀 root + 可寫資料分區。

## 12. 最終驗收矩陣

每一項都要用實機命令或現象確認：

- 通電自啟動：插入 4.2V 供電後自動 boot 到 Linux。
- OS：`cat /etc/os-release` 顯示 Ubuntu/Debian ARM64。
- Kernel：`uname -a` 顯示目標主線核心。
- USB console：Windows COM port 可登入。
- USB network：NCM 可上網或可用於維護。
- USB host / MCU：Klipper MCU 出現在 `/dev/serial/by-id/`。
- WiFi：NetworkManager 可連線並取得 IP。
- 觸控：`evtest` 有座標事件，HelixScreen 可操作。
- 顯示：開機後自動顯示 HelixScreen。
- Klipper/Moonraker：服務 active，HelixScreen 可連到 Moonraker。
- 恢復能力：fastboot、serial console、pstore/ramoops 至少一種可用。
