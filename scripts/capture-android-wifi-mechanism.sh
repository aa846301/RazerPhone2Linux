#!/usr/bin/env bash
#
# capture-android-wifi-mechanism.sh
#
# B 方向 (CLAUDE.md §5) capture: pull the *working* WiFi / modem (MSS) bring-up
# mechanism from stock Android on the Razer Phone 2 (razer-aura, SDM845 /
# WCN3990) to diff against the failing mainline-Linux MSS bring-up.
#
# Stock aura-p-release is a *user* build (no root). Items that need root
# (strace rmt_storage, dmesg, /dev/diag modem F3) are detected and clearly
# marked SKIPPED. Everything else works as adb 'shell' user. bugreport is the
# no-root substitute for a kernel-log snapshot.
#
# Prereq on phone: Developer options -> USB debugging ON + authorize RSA key.
#
# Usage:
#   bash scripts/capture-android-wifi-mechanism.sh [adb_path] [output_dir]

set -u

ADB="${1:-/mnt/c/Program Files/ASUS/GlideX/adb.exe}"
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
OUT="${2:-output/android-wifi-mechanism-$STAMP}"
REPO_FW="firmware/qcom/sdm845/Razer/aura"
mkdir -p "$OUT"

log()  { printf '%s\n' "$*" | tee -a "$OUT/run.log"; }

# save_sh <outfile> <remote command string...>
# All args are joined into ONE command string sent verbatim to the device shell
# (Windows adb.exe drops the quoting of a separate `sh -c '...'` arg, so pass the
# whole command — including pipes and for-loops — as a single quoted string).
save_sh() {
    local name="$1"; shift
    { echo "### adb shell $*"; "$ADB" shell "$*" 2>&1 | tr -d '\r' || true; } > "$OUT/$name"
}
pull_if() {
    local src="$1" dst="$2"
    if "$ADB" pull "$src" "$OUT/$dst" >>"$OUT/run.log" 2>&1; then
        log "  pulled  $src"
    else
        log "  (skip)  $src  (perm/SELinux denied or absent)"
    fi
}

log "== B-direction Android WiFi/MSS mechanism capture =="
log "adb: $ADB"
log "out: $OUT"

state="$("$ADB" get-state 2>/dev/null | tr -d '\r' || echo offline)"
if [ "$state" != "device" ]; then
    log "!! No authorized device (state=$state). Enable USB debugging + accept prompt."
    exit 1
fi
"$ADB" devices -l > "$OUT/00-devices.txt" 2>&1

# Root probe -------------------------------------------------------------------
ROOT=0
if "$ADB" shell 'id' 2>/dev/null | grep -q 'uid=0'; then ROOT=1; fi
if [ "$ROOT" = 0 ] && "$ADB" shell 'su -c id' 2>/dev/null | grep -q 'uid=0'; then ROOT=2; fi
log "[root] probe = $ROOT  (0=no root/user build, 1=adb root, 2=su available)"
SU() { if [ "$ROOT" = 2 ]; then "$ADB" shell "su -c '$*'"; else "$ADB" shell "$@"; fi; }

# 1. identity + firmware versions ----------------------------------------------
log "[1] properties + modem/wifi versions"
save_sh "01-getprop-all.txt"     getprop
save_sh "01-version-summary.txt" 'getprop | grep -iE "baseband|modem|ril|radio|build.(type|version|fingerprint)|product.(model|device|board)|board.platform|hardware|cnss|wlan|wcn|wifi|country|softap|crypto.state"'
save_sh "01-proc-version.txt"    cat /proc/version
save_sh "01-proc-cmdline.txt"    cat /proc/cmdline

# 2. (§5.1) live Android device-tree -> dtb -> dts -----------------------------
log "[2] device-tree (/sys/firmware/fdt -> dtc)"
if "$ADB" pull /sys/firmware/fdt "$OUT/02-android-live.dtb" >>"$OUT/run.log" 2>&1; then
    log "  pulled /sys/firmware/fdt"
    if command -v dtc >/dev/null 2>&1; then
        dtc -I dtb -O dts -o "$OUT/02-android-live.dts" "$OUT/02-android-live.dtb" 2>>"$OUT/run.log" \
            && log "  decoded -> 02-android-live.dts"
        # focused excerpts for the diff that matters (§5.1)
        for n in remoteproc reserved-memory regulator wifi ipa qcom,wcn; do
            grep -niE "$n" "$OUT/02-android-live.dts" 2>/dev/null
        done > "$OUT/02-dts-grep-hits.txt"
    fi
else
    log "  /sys/firmware/fdt denied; falling back to /proc/device-tree tar"
    save_sh "02-proc-dt-listing.txt" 'ls -R /proc/device-tree/soc | head -200'
fi

# 3. modem / subsystem state + firmware images (§5.5) --------------------------
log "[3] modem / subsystem state + PIL images"
save_sh "03-subsys-state.txt"    'for d in /sys/bus/msm_subsys/devices/subsys*; do echo "== $d"; cat "$d/name" 2>/dev/null; cat "$d/state" 2>/dev/null; done'
save_sh "03-remoteproc.txt"      'for r in /sys/class/remoteproc/remoteproc*; do echo "== $r"; cat "$r/name" 2>/dev/null; cat "$r/state" 2>/dev/null; cat "$r/firmware" 2>/dev/null; done'
save_sh "03-firmware-mnt-ls.txt" 'ls -lZ /vendor/firmware_mnt/image 2>/dev/null; echo "--- verinfo ---"; cat /vendor/firmware_mnt/verinfo/ver_info.txt 2>/dev/null'
log "    pulling /vendor/firmware_mnt/image (mba.mbn + modem.mdt/.b0x segments)"
pull_if /vendor/firmware_mnt/image   firmware_mnt-image

# 4. WiFi (WCN3990 / ath10k) firmware + config (§ board/bdwlan) ----------------
log "[4] WiFi firmware + config"
save_sh "04-wlan-fw-ls.txt"  'ls -lRZ /vendor/firmware/wlan 2>/dev/null; echo "---root mbn---"; ls -lZ /vendor/firmware/wlanmdsp.mbn /vendor/firmware/*wlan* /vendor/firmware/bdwlan* /vendor/firmware/firmware-5* /vendor/firmware/board-2* 2>/dev/null'
pull_if /vendor/firmware/wlan          wlan-fw
pull_if /vendor/firmware/wlanmdsp.mbn  wlanmdsp.mbn
pull_if /vendor/etc/wifi               vendor-etc-wifi

# 5. runtime wifi state (no root) ----------------------------------------------
log "[5] runtime wifi state"
save_sh "05-dumpsys-wifi.txt"         dumpsys wifi
save_sh "05-dumpsys-connectivity.txt" dumpsys connectivity
save_sh "05-net.txt" 'ip -o link; echo "---addr---"; ip -o addr; echo "---class/net---"; ls -l /sys/class/net'

# 6. (§5.3) how Android brings modem + wifi up: logcat -------------------------
log "[6] logcat radio/all (modem PIL / cnss / icnss / qmi / wlfw live here)"
save_sh "06-logcat-radio.txt" logcat -b radio -d -v time
save_sh "06-logcat-all.txt"   logcat -b all   -d -v time
# note: anchor 'pil' loosely but drop dex2oat 'comPILation' noise
save_sh "06-logcat-bringup-grep.txt" 'logcat -b all -d -v time | grep -iE "subsys|pil_|q6v5|cnss|icnss|ath10k|wlan|wcn|wlfw|wlan_pd|sysmon|fatal|crash|smem|rmt_storage" | grep -avE "dex2oat|compilation"'

# 6b. live WiFi off->on handshake (no root) -- userspace cnss/wlfw/supplicant path
log "[6b] live WiFi off->on toggle handshake"
"$ADB" shell 'logcat -c; svc wifi disable; sleep 4; svc wifi enable; sleep 9' >>"$OUT/run.log" 2>&1
save_sh "10-wifi-toggle-logcat.txt" 'logcat -b all -d -v time | grep -iE "cnss|wlfw|icnss|wlan0|wificond|supplicant|WLAN|ath10k|firmware" | grep -avE "dex2oat|compilation"'

# 7. (§5.2 / §5.4) root-only modem-internal visibility -------------------------
log "[7] root-only items (strace rmt_storage / dmesg / diag)"
if [ "$ROOT" != 0 ]; then
    save_sh "07-dmesg.txt" 'dmesg | grep -iE "pil|modem|mss|subsys|q6v5|wlan|cnss|icnss|ipa|qmi|wlfw|fatal|crash"'
    log "    strace rmt_storage for 8s (Ctrl flow handled by phone)"
    SU "sh -c 'p=\$(pidof rmt_storage); timeout 8 strace -f -tt -e trace=openat,read,pread64,lseek -p \$p 2>/tmp/rmt.strace; cat /tmp/rmt.strace'" > "$OUT/07-rmt_storage.strace" 2>&1 || true
    save_sh "07-diag-node.txt" 'ls -l /dev/diag'
else
    {
        echo "SKIPPED: stock user build, no root."
        echo "These three need root and are the only window into modem internals:"
        echo "  - strace rmt_storage  (§5.2: Android's modemst1/2 read order)"
        echo "  - dmesg pil/mss/cnss  (§5.3: kernel modem bring-up; see bugreport KERNEL LOG instead)"
        echo "  - /dev/diag modem F3  (§5.4: modem-internal QXDM/F3 log)"
        echo "To obtain: flash Magisk-patched boot or a userdebug build, then re-run."
    } > "$OUT/07-ROOT-REQUIRED.txt"
    log "    SKIPPED (no root) -> 07-ROOT-REQUIRED.txt"
fi

# 8. bugreport = no-root kernel-log snapshot -----------------------------------
if [ "${SKIP_BUGREPORT:-0}" != "1" ]; then
    log "[8] bugreport (no-root KERNEL LOG snapshot; ~1-2 min, SKIP_BUGREPORT=1 to skip)"
    if "$ADB" bugreport "$OUT/08-bugreport" >>"$OUT/run.log" 2>&1; then
        log "    bugreport saved"
        # extract KERNEL LOG (dmesg) -- holds this boot's modem PIL + WLAN bring-up
        BRZIP=$(ls "$OUT"/08-bugreport*.zip 2>/dev/null | head -1)
        if [ -n "$BRZIP" ] && command -v unzip >/dev/null 2>&1; then
            unzip -o -q "$BRZIP" -d "$OUT/bugreport-x"
            BRTXT=$(ls "$OUT"/bugreport-x/bugreport*.txt 2>/dev/null | head -1)
            if [ -n "$BRTXT" ]; then
                awk '/^------ KERNEL LOG \(dmesg\)/{f=1} f{print} /^------ SYSTEM LOG/{if(f)exit}' \
                    "$BRTXT" | tr -d '\r' > "$OUT/11-android-dmesg.txt"
                log "    extracted KERNEL LOG -> 11-android-dmesg.txt ($(wc -l <"$OUT/11-android-dmesg.txt") lines)"
                grep -aiE "pil-q6v5|pil_mss|MBA boot|Brought out of reset|wlan_pd|icnss.*(QMI Server|FW is ready)|IPA.*POWERUP|INIT_MODEM_DRIVER|sysmon.*modem|Assign modem memory" \
                    "$OUT/11-android-dmesg.txt" > "$OUT/11-modem-wlan-timeline.txt" 2>/dev/null
            fi
        fi
    else
        log "    bugreport failed"
    fi
fi

# 9. sha256: Android live firmware vs repo Linux firmware (§4/§5.5) -------------
log "[9] sha256 compare: Android-live vs repo $REPO_FW"
{
    echo "# file : android_sha256 : repo_sha256 : MATCH?"
    for f in mba.mbn wlanmdsp.mbn; do
        a=""; r=""
        [ -f "$OUT/firmware_mnt-image/$f" ] && a=$(sha256sum "$OUT/firmware_mnt-image/$f" | awk '{print $1}')
        [ -f "$OUT/$f" ] && a=$(sha256sum "$OUT/$f" | awk '{print $1}')
        [ -f "$REPO_FW/$f" ] && r=$(sha256sum "$REPO_FW/$f" | awk '{print $1}')
        m="?"; [ -n "$a" ] && [ "$a" = "$r" ] && m="YES"; [ -n "$a" ] && [ "$a" != "$r" ] && m="NO"
        echo "$f : ${a:-<none>} : ${r:-<none>} : $m"
    done
    echo "# NOTE: Android stores modem as modem.mdt + modem.b0x segments, repo modem.mbn"
    echo "#       is the squashed single file -> compare segments/structure, not a 1:1 sha."
    echo "# Android modem segments:"
    ls -l "$OUT/firmware_mnt-image"/modem.* 2>/dev/null
} > "$OUT/09-firmware-sha-compare.txt"
cat "$OUT/09-firmware-sha-compare.txt" | tee -a "$OUT/run.log"

log "== done -> $OUT =="
