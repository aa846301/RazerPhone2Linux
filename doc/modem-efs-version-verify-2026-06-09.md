# Razer Phone 2 Modem / EFS / Secure-Chain Version Verification - 2026-06-09

## Why this check

The MSS fatal happens after the modem authenticates, loads MPSS, reports
`running`, answers a single `tms/pddump_disabled` servreg lookup, then
fatal-errors with **no SSR reason** (SMEM 421 = -ENOENT), before `wlan/fw` /
WLFW. The whole generic postmarketOS SDM845/MSM8998 WLAN recipe is already
correctly applied (DTS firmware names, firmware files present, wlanmdsp beside
modem, pd-mapper/tqftpserv/qrtr/rmtfs, even the "diag-router before services"
workaround — all tested). So the remaining credible Razer-specific cause is a
**version mismatch between the modem firmware we load in Linux and the secure
boot chain / EFS that is actually flashed on the phone**.

Linux flashing only replaces `boot` / `system` / `vbmeta`. The phone keeps
whatever `xbl` / `tz` / `hyp` / `aop` / `keymaster` / `devcfg` / `abl` / `modem`
/ `dsp` were last flashed. A QC modem that loads cleanly but fatals with no
crash reason is a classic symptom of the modem image not matching the secure
environment (PIL/anti-rollback version) or running against wiped/foreign EFS.

## Baseline: versions we load + 3201 ROM (P-SMR6-RC001)

Extracted from `firmware/qcom/sdm845/Razer/aura/*` and
`aura-p-release-3201-user-full/aura-p-release-3201/*`:

| Component | Version string (3201 = what we load) |
| --- | --- |
| modem.mbn / modem.img | `MPSS.AT.4.0.c2-00888-SDM845_GEN_PACK-1` |
| mba.mbn | `MPSS.AT.4.0.c2-00888-SDM845_GEN_PACK-1` (same train) |
| tz.img | `TZ.XF.5.0.1.C5-00031` |
| hyp.img | `TZ.XF.5.0.1.C5-00031` |
| xbl.img | `BOOT.XF.2.0-00377-SDM845LZB-1` |
| dsp.img | `ADSP.HT.4.1-00094-SDM845` + `CDSP.HT.1.1-00097-SDM845` |
| wlanmdsp.mbn | `WLAN.HL.2.0.c10-00085-QCAHLSWMTPLZ-1` (2019, **different train** — only matters post-WLFW) |

The modem.mbn we load matches the 3201 modem.img exactly. mba is the same train.
The wlanmdsp.mbn is from a different (newer) WLAN build, but it is loaded only
after WLFW, so it is not the early-fatal cause; keep it noted for later.

## Step 1 - READ what is currently flashed (read-only, over SSH)

SSH into the phone (Linux is running) and check the partition labels first:

```sh
ls -l /dev/disk/by-partlabel/ | grep -iE 'modem|tz|hyp|xbl|aop|keymaster|devcfg|abl|dsp|fsg|fsc|modemst|persist'
```

Then dump the version strings actually on the device. Use the active slot suffix
you see above (`_a` or `_b`; drop the suffix if labels have none):

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

Compare line by line against the baseline table.

- **All match 3201** -> secure/modem versions are consistent; the early fatal is
  not a version mismatch. Move to the crash-reason path (see "QMI parse" below).
- **Anything differs** -> that is a real lead. Note especially if the phone shows
  a **newer** build than 3201 (higher `-00xxx` number or newer `TZ.XF`/`BOOT.XF`).

## Step 2 - Check EFS (modem calibration) is present, not wiped

EFS is per-device and is NOT in the ROM; it lives in `modemst1/modemst2/fsg/fsc`
and is served to the modem by rmtfs. A wiped/zeroed EFS makes the modem assert
extremely early with no crash reason — exactly our symptom.

```sh
sudo sh -c '
for p in modemst1 modemst2 fsg fsc; do
  d="/dev/disk/by-partlabel/$p"
  [ -e "$d" ] || { echo "$p: NO PARTITION"; continue; }
  bytes=$(dd if="$d" bs=1M count=8 2>/dev/null | tr -d "\0" | wc -c)
  echo "$p: $bytes non-zero bytes in first 8 MiB"
done'
```

- A few KiB+ of non-zero bytes -> EFS has data (good).
- ~0 non-zero bytes -> EFS is blank/wiped -> strong candidate for the fatal.

## Step 3 - CONDITIONAL reflash of the firmware/secure set (fastboot)

Only do this if Step 1 shows a mismatch **and the phone is NOT newer than 3201**.
Downgrading xbl/tz/abl below the device's anti-rollback version can hard-brick.

This subset re-aligns the secure chain + modem + dsp to 3201 while PRESERVING the
Linux install. It deliberately does NOT flash `boot`/`system`/`vendor`/`vbmeta`
and does NOT erase `userdata` (that is the Linux rootfs).

```powershell
# run from aura-p-release-3201-user-full\aura-p-release-3201
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

Notes / safety:

- Do NOT run the stock `flash_all.sh` — it erases `userdata` (your Linux rootfs)
  and flashes Android `boot`/`system`.
- `persist.img` is intentionally omitted (device sensor/cal data). Add it only if
  Step 2 also shows persist problems.
- Keep the cable solid; an interrupted xbl/tz flash can brick.
- After reflashing, the Linux `boot`/`rootfs` are untouched; just boot back into
  Linux and re-run the WiFi/MSS validation. Re-add the SSH key only if userdata
  was somehow reset.

## Alternative path - decode the actual crash reason (QMI parse kernel dump)

If Step 1/2 all match 3201 (no version/EFS mismatch), the fatal is not a version
problem and the real blocker is that we still have no modem assert reason. The
sdm845-mainline tool `qmi-parse-kernel-dump`
(https://gitlab.com/sdm845-mainline/qmi-parse-kernel-dump) parses a kernel /
remoteproc dump to recover QMI/SSR information. The catch on Razer: our previous
`devcoredump` was zero-filled (MPSS XPU-protected at fatal time), so this tool
needs a dump that actually contains modem memory first — i.e. a real DDR/EDL
ramdump or a working minidump, not the empty devcoredump. That is the next build
to design if the version check comes back clean.
