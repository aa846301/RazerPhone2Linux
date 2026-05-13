# Razer Phone 2 主線 Linux 移植基線

## 1. 專案目標

目標設備是 Razer Phone 2。

命名約定：
- 行銷名稱：Razer Phone 2
- Android/boot 體系常見代號：cheryl2
- 目前主線移植與 DTS 使用代號：aura

最終交付目標：
- 4.2V 電池保護板供電下可穩定通電自啟動
- 開機後自動進入 Debian/Ubuntu 使用者空間
- 自動啟動 KlipperScreen
- 顯示、觸控、WiFi、USB 主機模式可用
- 具備可維護、可重建、可除錯的完整移植流程與文件

這份文件不是 brainstorming，而是從第一性原理重新整理後的工程執行基線。

---

## 2. 第一性原理

移植工作本質上是五條鏈路依序閉合：

1. Boot chain
	Boot ROM -> bootloader -> kernel -> initramfs -> rootfs
2. Hardware description
	SoC 基礎描述 -> 板級 regulator/GPIO/bus -> 周邊節點 -> 相依關係
3. Observability
	至少要有一條穩定的早期診斷通道，不依賴螢幕成功初始化
4. Feature bring-up
	顯示、觸控、WiFi、USB 逐項驗證，每次只改一個主要變數
5. Productization
	自動開機、自動登入、自動啟動 KlipperScreen、長時間穩定性

如果第 3 點沒有建立，後面的 bring-up 都會變成盲刷。
所以目前專案的首要矛盾不是功能不足，而是早期可觀測性不足。

---

## 3. 現況清理

### 3.1 已完成且可重用的部分

- WSL 建置環境已可用
- sdm845-mainline 內核可編譯
- 自訂 DTS 已建立，檔案在 [dts/sdm845-razer-aura.dts](dts/sdm845-razer-aura.dts)
- 自訂 NT36830 面板驅動已建立，檔案在 [panel-driver/panel-novatek-nt36830.c](panel-driver/panel-novatek-nt36830.c)
- boot.img 製作流程可用，且已能 fastboot 刷入
- rootfs 建置腳本已存在
- USB DWC3 OTG 基礎節點已在 DTS 啟用

### 3.2 當前主要阻塞

- 最新 boot.img 刷入後，症狀為花屏後黑屏
- 白屏問題已不再是主症狀，代表面板狀態與先前不同，但仍未達到可用顯示
- 目前 initramfs 是 static init only，失敗時不提供 shell
- 目前早期除錯不具備可靠的 USB gadget 診斷路徑
- 目前 rootfs 端雖有 ttyGS0 規劃，但它依賴 rootfs 已成功掛載與 systemd 已啟動

### 3.3 現在不能再做的事

- 不能再把面板修正、USB gadget、rootfs 啟動、KlipperScreen 併進同一張 image 驗證
- 不能把 USB 網卡當成目前的首要救援手段
- 不能把黑屏直接等價成 kernel 沒跑起來

---

## 4. 工程策略

從現在開始，整個專案拆成三種映像，不混用：

### 4.1 debug-boot

用途：只解決「我能不能看到系統在做什麼」

特徵：
- busybox initramfs
- 早期 shell fallback
- 內建 USB serial gadget 或其他早期診斷通道
- 可選保守顯示路徑，例如 simpledrm / bootloader framebuffer 保留
- 不追求 rootfs 完整啟動
- 不追求面板主驅動完成

接受標準：
- 至少能穩定取得以下任一項
  - UART log
  - USB serial log
  - 螢幕上的固定診斷畫面或輪播診斷文字

### 4.2 boot-rootfs

用途：只驗證 kernel + initramfs + userdata rootfs 是否完整接通

特徵：
- 已有早期診斷能力
- rootfs 可掛載
- 可登入 shell
- 可檢查 dmesg、lsmod、sysfs、drm、usb、input、wifi

接受標準：
- rootfs 成功掛載
- 可透過 UART/ttyGS0/SSH 任一方式登入
- 可以在機內收集日誌，不再靠猜

### 4.3 feature-boot

用途：逐項 bring-up 顯示、觸控、WiFi、USB host、KlipperScreen

特徵：
- 只在 debug-boot 和 boot-rootfs 成功後推進
- 每次只推一個主要子系統

---

## 5. 重新規劃後的正式流程

## Phase A: 建立可觀測性

這是現在的最高優先級。

### A.1 建立 debug boot image

目標：讓失敗可見。

實作內容：
- 改用 busybox initramfs，而不是現在的 static init only initramfs
- initramfs 中加入以下能力
  - 掛載 proc、sys、dev、devpts
  - 列印 cmdline、分割區、partlabel、drm 狀態、USB 狀態
  - root 掛載失敗時掉入 shell，而不是直接 halt
  - 支援將關鍵資訊循環輸出到 console，方便手機拍照一次取證
- 若條件允許，將 USB serial gadget 做成 early debug 通道

驗證輸出：
- 一張專用 debug boot.img
- 一份明確的啟動輸出清單

### A.2 調整 kernel config 為 debug 優先

原則：先讓診斷通道內建，不依賴 rootfs 模組載入。

需確認與調整：
- USB serial gadget 優先考慮 built-in，而非 module
- pstore / ramoops 啟用，保留崩潰後資訊
- simpledrm 或 framebuffer console 保持可用
- 不要在 debug image 中同時承載高風險面板實驗

### A.3 決定 debug image 的顯示策略

顯示策略分兩條，不混合：

1. 保守顯示路線
	保留 bootloader framebuffer / simpledrm，只求看到字

2. 面板主驅動路線
	只在可觀測性完成後再做

結論：
在 debug-boot 階段，不應把 NT36830 full bring-up 當主路線。

---

## Phase B: 打通 kernel -> initramfs -> rootfs

### B.1 驗證 userdata rootfs 掛載鏈

目標：確認真正的 Linux 使用者空間能起來。

檢查點：
- UFS 裝置節點是否穩定出現
- partlabel 掃描是否正確
- userdata 是否能以 ext4 掛載
- /sbin/init 是否存在且可 exec
- rootfs 中的 libc、systemd、udev、modules 是否匹配 kernel 版本

### B.2 rootfs 只先做最小可登入版

不要一開始就追 KlipperScreen。

第一版 rootfs 目標：
- 開機進 multi-user.target
- 可以用 ttyMSM0 或 ttyGS0 登入
- 可以手動看 dmesg、lsmod、ip link、evtest

rootfs 最小套件集合：
- systemd-sysv
- udev
- bash
- kmod
- iproute2
- network-manager
- openssh-server
- initramfs-tools
- evtest
- usbutils
- pciutils
- nano 或 vim

### B.3 rootfs 驗收標準

必須同時滿足：
- 可穩定掛 root
- 可登入 shell
- 能收集日誌

若 B 階段未完成，不進入 KlipperScreen。

---

## Phase C: DTS 與板級描述收斂

這一階段的原則是：
設備樹必須完整，不留推託型空洞；但 bring-up 順序仍然分級。

### C.1 DTS 的角色

DTS 不是把 Android 節點逐字搬運，而是把主線內核真正需要的硬體描述完整落地：

- regulator topology
- GPIO polarity
- interconnect and bus relationships
- PHY and controller supplies
- pinctrl states
- interrupt lines
- reserved-memory
- chosen/stdout-path
- panel / touch / wifi / usb / ufs / uart / pmic 配置

### C.2 DTS 撰寫順序

1. SoC 繼承與 board identity
2. regulator 與固定電源軌
3. storage 與 console
4. USB 與 debug paths
5. touch 與 WiFi
6. display
7. audio 與非核心周邊
8. power-on / charger / battery behavior

### C.3 現階段 DTS 工作重點

不是從零開始重寫，而是做一致性收斂：

- 對照 Android DTS 校正 regulator 名稱、電壓、相依關係
- 對照主線相近機種校正 usb、wifi、touch、ufs 寫法
- 明確區分哪些節點已經驗證、哪些節點只完成靜態描述但未 runtime 驗證

---

## Phase D: 顯示子系統 bring-up

顯示是目前最高風險子系統，但不能再讓它支配整個專案節奏。

### D.1 顯示 bring-up 原則

1. 先求可觀測，不先求完整畫面
2. 先求穩定，再求高刷新率
3. 先求最少變數，再求 Android 對齊

### D.2 顯示 bring-up 分層

Layer 1: 保留 bootloader framebuffer 或 simpledrm
- 目標是取得文字輸出

Layer 2: 面板電源與 reset 時序正確
- 驗證 prepare/unprepare 不會立刻把面板送進錯誤狀態

Layer 3: 最小 panel on/off 穩定
- 先確認不是黑屏或亂屏後立即掉電

Layer 4: 完整初始化序列
- 對齊官方 Android DTS

Layer 5: dual-DSI + DSC + 目標模式
- 最後才談 120Hz 與完整時序

### D.3 當前判斷

目前症狀從白屏變成花屏後黑屏，說明面板狀態已被改變，但仍未建立穩定 working state。
因此下一步不應直接再增加更多 panel 命令，而應先把 debug-boot 做出來，讓每次刷機都能帶出可用訊息。

---

## Phase E: USB bring-up

USB 需求實際上有三種，必須拆開：

1. Early debug USB
	用於除錯，不依賴 rootfs

2. Linux gadget USB
	用於登入、日誌、必要時網路診斷

3. USB host mode
	用於與 Klipper 下位機通訊

### E.1 優先順序

先做 early debug USB serial。
再做 rootfs 起來後的 ttyGS0。
最後才做 USB 網卡與 host mode 驗證。

### E.2 對 USB 網卡的判斷

USB 網卡不是沒用，但不是現在最有價值的第一步。

原因：
- 需要更多 kernel config 與 gadget 組態
- 需要 rootfs 或 initramfs 主動設定網路
- 如果目前卡在更早期，USB 網卡不會自然救你

結論：
現階段先做 USB serial，比 USB ethernet 更有工程回報。

---

## Phase F: 觸控與 WiFi bring-up

這兩項都應在 boot-rootfs 可登入後展開。

### F.1 觸控

目標：
- input device 枚舉正常
- 中斷與 reset GPIO 正確
- evtest 可觀察事件
- 後續再做座標矩陣與方向校正

### F.2 WiFi

目標：
- ath10k_snoc 載入
- firmware 檔存在且匹配
- wlan0 枚舉
- NetworkManager 可掃描 AP

### F.3 原則

這兩項都不應在黑屏、無 shell、無早期 log 的狀態下硬推。

---

## Phase G: KlipperScreen 產品化

只有在以下條件成立後才進入：

- 顯示穩定
- 觸控可用
- USB host 可與下位機通訊
- rootfs 穩定
- 能長時間自動啟動

### G.1 先決條件

- 不先上完整桌面
- 優先 kiosk 模式
- 優先穩定啟動與自動恢復

### G.2 實作建議

- 初期可先用 X11/fbdev 跑 KlipperScreen
- 若後續 DRM/GBM 路徑成熟，再評估更輕量 kiosk 組合

---

## Phase H: 通電自啟動與電源策略

這是最後的產品化收尾，不是現在的阻塞點。

原因：
- 它牽涉 PMIC PON、充電器策略、硬體供電實況
- 若在系統尚未穩定前處理，會把問題空間再放大

進入條件：
- 系統已能穩定從按鍵開機
- 主要周邊已基本可用
- 可重複量測待機與上電行為

---

## 6. 里程碑與驗收標準

### M0: 工具鏈里程碑
- 內核可重建
- DTS 可編譯
- boot.img 可重建並刷入

目前狀態：已達成

### M1: 早期可觀測性里程碑
- debug boot image 可穩定輸出早期資訊
- root 掛載失敗時可停在 shell 或可讀診斷畫面

目前狀態：未達成，這是當前最高優先級

### M2: 可登入 Linux 里程碑
- rootfs 可掛載
- 可進入 shell
- 能在機內抓 dmesg 與 sysfs 狀態

### M3: 顯示輸入連通里程碑
- 顯示穩定
- 觸控穩定

### M4: 網路與外設里程碑
- WiFi 可連線
- USB host 可與下位機通訊

### M5: 產品化里程碑
- 開機自動登入
- 自動啟動 KlipperScreen
- 通電自啟動

---

## 7. 當前版本之後的執行順序

這是接下來真正要執行的順序。

1. 製作 debug-boot 版本
	- busybox initramfs
	- shell fallback
	- 早期診斷輸出
	- 以 simpledrm / 保守顯示路線為優先

2. 將 USB early debug 路徑內建化
	- 優先 USB serial
	- 不先追 USB ethernet

3. 驗證 rootfs 掛載與可登入 shell

4. 建立機內日誌採集流程
	- dmesg
	- drm 節點
	- regulators
	- usb role 與 gadget 狀態
	- input / wifi 裝置枚舉

5. 回頭處理 NT36830 panel bring-up
	- 以可觀測資料為依據，而不是盲改序列

6. 完成 touch、wifi、USB host

7. 最後才接 KlipperScreen 與通電自啟動

---

## 8. 現在的判斷結論

基於目前進度，專案不需要重新從零開始。
真正需要的是把工作流從「功能堆疊模式」切回「診斷優先模式」。

簡單說：

- boot.img 建置與刷機鏈路已經打通
- 問題不在於沒有流程，而在於目前流程缺少 debug image 這個中間層
- 下一步不是先修 USB 網卡，也不是直接繼續堆面板命令
- 下一步是先做一張可靠的 debug-boot，讓之後所有問題都能在機內被觀察與定位

這份文件作為後續移植的新的基線。