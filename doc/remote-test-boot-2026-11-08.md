# 遠端測試開機與 DMIC routing（2026-11-08）

目的：讓 kernel／DTB 的修改能遠端驗證，不需要使用者每次接 fastboot。

## 實機盤點（實機已確認）

- WiFi SSH：`klipper@192.168.10.184`，金鑰登入，sudo 已設為免密碼。
- Ubuntu 24.04、`7.1.0-rc1-sdm845`（7/24 編譯）、RAM 7.5 GB、rootfs 在 `userdata`。
- 目前從 `_a` 開機，`_a` 已標記 Successful；`_b` 可開機但未標記 Successful。
- boot.img header v1、page 4096；DTB 附加在 Image.gz 後面（116994 bytes）。
  `boot_a` 分割區在映像檔結尾之後還有 24 MB 非零的舊資料，判斷是之前刷入時留下的。

## 為什麼不用 A/B 切換槽位來回退

逐一比對 `_a`/`_b` 的雜湊：除了 `dtbo`、`mdtp`、`systeminfo`，其餘的
`xbl`、`xbl_config`、`abl`、`tz`、`hyp`、`aop`、`keymaster`、`cmnlib*`、`devcfg`、
`qupfw`、`storsec`、`modem`、`dsp`、`bluetooth`、`vbmeta`、`boot` **全部不同**。
`qbootctl -s` 會連 UFS 開機 LUN 一起切換，所以切到 `_b` 就等於換一整套 bootloader 韌體，
可能卡在 rollback 或 verity，最壞會掉進 EDL。在確認 `_b` 的韌體版本之前，**不使用切換槽位的回退方式**。

## 方案：kexec 試跑（不寫入任何分割區）

1. `tools/bootimg-swap-dtb.py --extract boot_a.img DIR`：取出 Image.gz、DTB、ramdisk。
   用原本的 DTB round-trip 時，輸出和 `boot_a` 逐位元組相同（實機已驗證）。
2. 用 `fdtput` 修改 DTB（只改目標屬性，跟正在跑的 kernel 完全對得上）。
3. `razer-kexec-trial Image.gz new.dtb ramdisk [grace]`：
   - 用 `KExecWatchdogSec=30s` 讓 qcom-wdt 在 kexec 期間保持啟動。主線 `qcom-wdt.c`
     沒有呼叫 `watchdog_stop_on_reboot`，probe 時偵測到 watchdog 正在跑會設定
     `WDOG_HW_RUNNING` 並由 kernel 持續 ping（文件已確認，**實機尚未驗證**）。
   - cmdline 會加上 `razer.trial=<秒>`。`razer-trial-guard` 在時間內沒看到
     `/run/razer-trial-ok` 就自動重開機，回到 `boot_a`。
4. 試跑通過之後，才用 `bootimg-swap-dtb.py` 產生正式映像檔寫入 `boot_a`，原始映像檔另外備份。

尚未驗證的風險：
- watchdog bite 之後，手機可能進入 Qualcomm ramdump 模式，而不是正常重開機。這要靠第一次測試確認，
  需要使用者在手機旁邊，必要時長按電源鍵。
- kexec 之後，ADSP／modem 等 remoteproc 可能沒辦法重新初始化，WiFi 也可能起不來。這時會由 guard 負責重開機。

## DMIC routing 修正

- 原廠 `sdm845-audio_rc2-evb.dtsi`：DMIC1←MIC BIAS1、DMIC3←MIC BIAS3、DMIC5←MIC BIAS4。
- 原本的板級 DTS 照抄通用的 AMIC1–5 routing，不符合這片主機板。
- 修正前的實機基準：`MultiMedia2 Mixer SLIMBUS_0_TX` → `AIF1_CAP Mixer SLIM TX0` →
  `CDC_IF TX0 MUX=DEC0` → `ADC MUX0=DMIC` → `DMIC MUX0=DMIC1/3/5`，`arecord -D hw:0,1`
  48 kHz mono 錄 3 秒。PCM 有正常串流，ADSP 沒有逾時，但 DMIC1/DMIC3 全部是 0，
  DMIC5 的最大值只有 10。這和 MIC BIAS 沒有開的情況吻合。
- 已修改 `dts/sdm845-razer-aura.dts`，並在手機上用 fdtput 產生 `~/abwork/dmic.dtb`
  （和原本的 DTB 相比只差 `audio-routing`）。

## 2026-11-09 實機結果

### 關機卡 15 分鐘以上：已找到原因並修正（實機已驗證）

用 `razer-shutdown-hang-dump`（關機後 45 秒和 2 分鐘各執行一次 `sysrq w`）拍下的 stack 顯示這是一個死結：
`razer-modem-stop` 停止 ADSP → `ssr_notify_stop` → `qcom_slim_ngd_ssr_pdr_notify()` 持有
NGD `tx_lock` → `slim_report_absent` → `wcd934x_slim_status` → 移除 SoundWire 子裝置
時 runtime resume → `clk_prepare()` 拿走全域的 `prepare_lock` → `swclk_gate_enable` 經過
SLIMbus 寫入 → `qcom_slim_ngd_xfer_msg` 又要拿同一把 `tx_lock`。被佔住的 `prepare_lock` 連帶
卡住 `sugov`（cpufreq）和 UFS runtime PM，所以 jbd2、journald、NetworkManager 等所有要寫入的程式都進入 D 狀態。
這是主線 kernel 本身的程式碼路徑，專案的 0015 patch 沒有改到這段。

修正：`razer-modem-stop` 改成只停 MSS（`4080000.remoteproc`）。套用後一般重開機約 30 秒完成，
journal 也完整記錄到 `systemd-shutdown`。kernel 端的正式修正（在 `ssr_pdr_notify` 裡不要
持有 `tx_lock` 去呼叫 `qcom_slim_ngd_down`）尚未進行。

### kexec 試跑：這台機器目前不可行

- 第 1 次：kexec 前的關機被上面的死結卡住約 15 分鐘，之後 qcom-wdt 在約 30 秒內把手機重置回
  `boot_a`。**watchdog 保護實機已驗證**，沒有進入 ramdump。
- 第 2 次：WiFi 還連著就停 MSS，也停了 ADSP（死結），沒有任何畫面。
- 第 3 次（只停 MSS）：新 kernel 開機到大約 14 秒，出現 `Error sending AMC RPMH requests (-110)`
  （RPMh TCS 狀態沒有在 kexec 時重設）；45 秒時 `crash detected in adsp: type watchdog`（ADSP 一直跑進新 kernel）。
- 結論：要讓 kexec 可行，得先修 kernel（kexec 時重設 rpmh-rsc，並修掉 SLIMbus 死結讓 ADSP 能安全停止）。
  在那之前，低風險的 DTB 修改改成直接寫入 `boot_a`，救援方式是用 fastboot 刷回
  `output/backup/boot_a-2026-11-08.img`。

### DMIC routing（實機已驗證：DTB 已生效，收音品質待確認）

- `boot-dmic.img` 已寫入 `boot_a`，讀回的 sha256 為 `cbe32dc6…`，開機正常，
  `/sys/firmware/fdt` 裡的 `/sound audio-routing` 已經是 DMIC1/3/5 ← MIC BIAS1/3/4。
- 安靜環境下錄 3 秒：開頭 100–300 ms 有偏壓穩定時的爆音，之後三顆麥克風的 RMS 都約 10
  （大約 −70 dBFS）。修正前 DMIC1/3 錄到的是全 0。
- 10 秒說話測試：RMS 只在 9–22 之間，聲音有沒有真的被收進來還要再確認（錄音檔在 `output/audio-tests/`）。
