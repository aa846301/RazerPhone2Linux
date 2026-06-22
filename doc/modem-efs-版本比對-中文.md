# Razer Phone 2 modem／EFS／安全鏈 版本比對（中文）

## 為什麼要做這個檢查

MSS fatal 發生在：modem 通過認證 → 載入 MPSS → 回報 `running` → 回應一筆
`tms/pddump_disabled` servreg 查詢 → 然後就 **沒有留下任何 SSR 原因**
（SMEM 421 = -ENOENT）地 fatal，發生在 `wlan/fw` / WLFW 出現之前。

整份通用的 postmarketOS SDM845/MSM8998 WLAN 配方都已經正確套用（DTS 韌體檔名、
韌體檔放好、wlanmdsp 與 modem 同目錄、pd-mapper/tqftpserv/qrtr/rmtfs、甚至
「diag-router 先於服務啟動」的 workaround 都測過）。所以剩下最可能、又屬於
Razer 這台裝置特定的原因是：**我們在 Linux 載入的 modem 韌體，與手機上實際燒著的
安全啟動鏈／EFS 版本不一致。**

刷 Linux 時我們只換 `boot` / `system` / `vbmeta`，手機保留著上次燒的
`xbl` / `tz` / `hyp` / `aop` / `keymaster` / `devcfg` / `abl` / `modem` / `dsp`。
modem 能乾淨載入卻無原因 fatal，正是 modem 影像和安全環境（PIL／防降級版本）
對不上、或跑在被清空/外來的 EFS 上的典型症狀。

## 基準：我們載入的版本 ＋ 3201 ROM（P-SMR6-RC001）

從 `firmware/qcom/sdm845/Razer/aura/*` 和
`aura-p-release-3201-user-full/aura-p-release-3201/*` 抽出來：

| 元件 | 版本字串（3201＝我們載入的） |
| --- | --- |
| modem.mbn / modem.img | `MPSS.AT.4.0.c2-00888-SDM845_GEN_PACK-1` |
| mba.mbn | `MPSS.AT.4.0.c2-00888-SDM845_GEN_PACK-1`（同一個建置列） |
| tz.img | `TZ.XF.5.0.1.C5-00031` |
| hyp.img | `TZ.XF.5.0.1.C5-00031` |
| xbl.img | `BOOT.XF.2.0-00377-SDM845LZB-1` |
| dsp.img | `ADSP.HT.4.1-00094-SDM845` ＋ `CDSP.HT.1.1-00097-SDM845` |
| wlanmdsp.mbn | `WLAN.HL.2.0.c10-00085-QCAHLSWMTPLZ-1`（2019，**不同建置列**，只影響 WLFW 之後） |

我們載入的 modem.mbn 與 3201 的 modem.img 完全相同，mba 也同一列。
wlanmdsp.mbn 是另一條（較新的）WLAN 建置，但它只在 WLFW 之後才載入，
所以不是早期 fatal 的原因，先記著留待後面。

## 第 1 步：讀取「手機目前實際燒的版本」（唯讀，透過 SSH）

SSH 進手機（Linux 正在跑），先看分割區標籤：

```sh
ls -l /dev/disk/by-partlabel/ | grep -iE 'modem|tz|hyp|xbl|aop|keymaster|devcfg|abl|dsp|fsg|fsc|modemst|persist'
```

再把裝置上實際的版本字串 dump 出來（用你上面看到的 slot 後綴 `_a` 或 `_b`；
若標籤沒有後綴就拿掉）：

```sh
sudo sh -c '
for p in modem_a tz_a hyp_a xbl_a dsp_a; do
  d="/dev/disk/by-partlabel/$p"
  [ -e "$d" ] || continue
  echo "== $p =="
  dd if="$d" bs=1M count=96 2>/dev/null | strings -n 8 | \
    grep -oE "MPSS\.AT\.[0-9.a-z-]+SDM845[A-Za-z_-]*|TZ\.[A-Z]+\.[0-9.A-Za-z-]+|BOOT\.XF\.[0-9.A-Za-z-]+SDM845[A-Za-z_-]*|ADSP\.HT\.[0-9.A-Za-z-]+|CDSP\.HT\.[0-9.A-Za-z-]+" | \
    sort -u | head
done'
```

逐行跟上面的基準表比對：

- **全部都符合 3201** → 安全鏈／modem 版本一致，早期 fatal 不是版本問題，
  改走抓崩潰原因的路（見最後一節 QMI parse）。
- **有任何不同** → 這就是真正的線索。特別注意手機是不是顯示**比 3201 還新**
  的版本（更大的 `-00xxx` 編號，或更新的 `TZ.XF`／`BOOT.XF`）。

## 第 2 步：檢查 EFS（modem 校準資料）是否存在、沒被清空

EFS 是每台裝置專屬、不在 ROM 裡，存在 `modemst1/modemst2/fsg/fsc`，由 rmtfs
餵給 modem。被清空/全零的 EFS 會讓 modem 在極早期就 assert、且沒有崩潰原因——
正是我們的症狀。

```sh
sudo sh -c '
for p in modemst1 modemst2 fsg fsc; do
  d="/dev/disk/by-partlabel/$p"
  [ -e "$d" ] || { echo "$p: 沒有這個分割區"; continue; }
  bytes=$(dd if="$d" bs=1M count=8 2>/dev/null | tr -d "\0" | wc -c)
  echo "$p: 前 8 MiB 內有 $bytes 個非零位元組"
done'
```

- 有數 KiB 以上非零位元組 → EFS 有資料（正常）。
- 接近 0 → EFS 被清空/空白 → 高度可疑，很可能就是 fatal 的原因。

## 第 3 步：條件式重刷 韌體/安全分區（fastboot）

只有在第 1 步發現版本不符、**且手機不比 3201 新**時才做。
把 xbl/tz/abl 降級到低於裝置防降級版本，可能硬磚。

這組指令把安全鏈＋modem＋dsp 重新對齊到 3201，同時**保留 Linux**：
刻意不刷 `boot`/`system`/`vendor`/`vbmeta`，也不 erase `userdata`（那是 Linux 根檔案系統）。

```powershell
# 在 aura-p-release-3201-user-full\aura-p-release-3201 資料夾裡執行
fastboot flash xbl_a xbl.img;            fastboot flash xbl_b xbl.img
fastboot flash xbl_config_a xbl_config.img; fastboot flash xbl_config_b xbl_config.img
fastboot flash tz_a tz.img;              fastboot flash tz_b tz.img
fastboot flash hyp_a hyp.img;            fastboot flash hyp_b hyp.img
fastboot flash aop_a aop.img;            fastboot flash aop_b aop.img
fastboot flash keymaster_a keymaster.img; fastboot flash keymaster_b keymaster.img
fastboot flash cmnlib_a cmnlib.img;      fastboot flash cmnlib_b cmnlib.img
fastboot flash cmnlib64_a cmnlib64.img;  fastboot flash cmnlib64_b cmnlib64.img
fastboot flash devcfg_a devcfg.img;      fastboot flash devcfg_b devcfg.img
fastboot flash qupfw_a qupfw.img;        fastboot flash qupfw_b qupfw.img
fastboot flash ImageFv_a ImageFv.img;    fastboot flash ImageFv_b ImageFv.img
fastboot flash abl_a abl.img;            fastboot flash abl_b abl.img
fastboot flash modem_a modem.img;        fastboot flash modem_b modem.img
fastboot flash dsp_a dsp.img;            fastboot flash dsp_b dsp.img
fastboot --set-active=a
fastboot reboot
```

注意／安全事項：

- 不要直接跑原廠的 `flash_all.sh`——它會 erase `userdata`（你的 Linux 根檔案
  系統）並刷 Android 的 `boot`/`system`。
- 刻意省略 `persist.img`（裝置感測器/校準資料）。只有第 2 步也顯示 persist 有問題
  時才加它。
- 傳輸線要穩；xbl/tz 刷到一半中斷可能變磚。
- 重刷後 Linux 的 `boot`/`rootfs` 沒被動到，直接開回 Linux 重跑 WiFi/MSS 驗證即可。
  只有在 userdata 被重置時才需要重新放 SSH 金鑰。

## 備案：抓出真正的崩潰原因（QMI parse kernel dump）

如果第 1／2 步全部都符合 3201（版本與 EFS 都沒問題），那 fatal 就不是版本問題，
真正的卡點是我們還沒拿到 modem 的 assert 原因。這時就走
`qrtr-qmi-dump-擷取與解析-中文.md` 那份流程：用 `0005-qrtr-qmi-dump.patch`
把 modem fatal 前的 QMI 對話抓出來、用 `parse_qmi_kernel_dump` 解析。
```
