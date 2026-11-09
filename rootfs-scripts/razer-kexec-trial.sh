#!/bin/bash
# Boot a candidate kernel/DTB through kexec without writing any partition.
#
# Why: the factory _b firmware slot (xbl/abl/tz/hyp/aop/modem/vbmeta) differs
# from _a on this phone, so A/B slot switching is not a safe fallback. kexec
# keeps boot_a untouched; any reboot returns to the known-good boot_a image.
#
# Safety nets (status: 文件已確認 from source, 實機尚未驗證):
#   1. systemd KExecWatchdogSec arms qcom-wdt for the kexec transition. The
#      mainline qcom-wdt driver does not stop on reboot/kexec and marks a
#      running watchdog WDOG_HW_RUNNING on probe, so a hang before or after the
#      module loads ends in a hardware bite and a cold boot of boot_a.
#   2. razer.trial=<seconds> is added to the cmdline. razer-trial-guard reboots
#      unless /run/razer-trial-ok is created within that time (e.g. over SSH),
#      which covers a kernel that is alive but lost WiFi/SSH.
#
# Usage: razer-kexec-trial KERNEL DTB INITRD [GRACE_SECONDS]
#   KERNEL may be an arm64 Image or Image.gz. The candidate kernel must have
#   the same release as the running one unless its modules are installed.
set -euo pipefail

if [ $# -lt 3 ]; then
    echo "usage: razer-kexec-trial KERNEL DTB INITRD [GRACE_SECONDS]" >&2
    exit 2
fi
if [ "$(id -u)" != 0 ]; then
    echo "ERROR: run as root" >&2
    exit 1
fi

KERNEL=$1
DTB=$2
INITRD=$3
GRACE=${4:-300}

for f in "$KERNEL" "$DTB" "$INITRD"; do
    [ -s "$f" ] || { echo "ERROR: missing or empty: $f" >&2; exit 1; }
done
case "$GRACE" in ''|*[!0-9]*) echo "ERROR: GRACE_SECONDS must be an integer" >&2; exit 2 ;; esac
command -v kexec >/dev/null || { echo "ERROR: kexec-tools not installed" >&2; exit 1; }
fdtget "$DTB" / compatible >/dev/null || { echo "ERROR: $DTB is not a valid DTB" >&2; exit 1; }
[ -e /dev/watchdog0 ] || { echo "ERROR: /dev/watchdog0 missing; refusing to kexec without a watchdog" >&2; exit 1; }

WORK=/run/razer-kexec
rm -rf "$WORK"
mkdir -p "$WORK"
if gzip -t "$KERNEL" 2>/dev/null; then
    zcat "$KERNEL" > "$WORK/Image"
else
    cp "$KERNEL" "$WORK/Image"
fi

CMDLINE=$(sed -E 's/(^| )razer\.trial=[^ ]*//g' /proc/cmdline)
if [ "${RAZER_KEXEC_VERBOSE:-1}" = 1 ]; then
    # Print the trial kernel's boot log on the panel so a hang can be
    # photographed: drop the quiet/blank switches and raise the loglevel.
    CMDLINE=$(echo " $CMDLINE " | sed -E \
        -e 's/ razer_quiet_console / /g' \
        -e 's/ razer_panel_idle_blank / /g' \
        -e 's/ (rd\.)?systemd\.show_status=[^ ]*/ /g' \
        -e 's/ loglevel=[^ ]*/ /g' \
        -e 's/ +/ /g; s/^ //; s/ $//')
    CMDLINE="$CMDLINE loglevel=7 ignore_loglevel"
fi
CMDLINE="$CMDLINE razer.trial=$GRACE"

# Keep qcom-wdt armed while systemd shuts down and jumps into the new kernel.
# qcom-wdt max timeout on SDM845 is ~31 s (0xFFFFF ticks @ 32768 Hz).
mkdir -p /run/systemd/system.conf.d
cat > /run/systemd/system.conf.d/90-razer-kexec-watchdog.conf <<'EOF'
[Manager]
KExecWatchdogSec=30s
EOF
systemctl daemon-reexec

kexec --unload 2>/dev/null || true
kexec -l "$WORK/Image" --dtb="$DTB" --initrd="$INITRD" --command-line="$CMDLINE"

{
    echo "time=$(date -Is)"
    echo "kernel=$KERNEL sha256=$(sha256sum "$KERNEL" | cut -d' ' -f1)"
    echo "dtb=$DTB sha256=$(sha256sum "$DTB" | cut -d' ' -f1)"
    echo "initrd=$INITRD"
    echo "grace=$GRACE"
} > /var/lib/razer-kexec-trial.last

echo "kexec loaded; cmdline: $CMDLINE"
sync

# 2026-11-08 first trial: the full systemd shutdown took ~15 min because
# NetworkManager, journald, systemd-backlight and the /tmp unmount were stuck
# in the kernel, and the kexec'd kernel then never came up (watchdog reset to
# boot_a after ~30 s). The mainline q6v5 remoteproc drivers have no .shutdown
# hook, so ADSP/CDSP/SLPI/MSS keep running into the next kernel. Stop them
# first so the trial kernel finds the DSPs in reset, then skip per-service
# stop jobs (systemd-shutdown still kills, syncs and unmounts).
if [ "${RAZER_KEXEC_STOP_RPROC:-1}" = 1 ]; then
    # Same order as razer-shutdown-prepare + razer-modem-stop: freeze UFS
    # clock scaling, let ath10k disconnect while MSS/WMI is still alive, and
    # only then stop the remoteprocs. Trial 2 stopped MSS with wlan0 still up
    # and hung with no further log.
    ufs_clkscale=/sys/bus/platform/devices/1d84000.ufshc/clkscale_enable
    [ -w "$ufs_clkscale" ] && printf '0' > "$ufs_clkscale" 2>/dev/null || true
    nmcli radio wifi off 2>/dev/null || true
    ip link set wlan0 down 2>/dev/null || true
    sleep 2
    sync
    # Never stop ADSP here: its SSR notification deadlocks the SLIMbus NGD
    # tx_lock against the WCD9340/SoundWire clk_prepare path (see
    # razer-modem-stop in apply-runtime-config.sh). Stop MSS only.
    for r in /sys/class/remoteproc/remoteproc*; do
        [ "$(cat "$r/name")" = 4080000.remoteproc ] || continue
        [ "$(cat "$r/state")" = running ] || continue
        echo "stopping $(cat "$r/name")"
        timeout 20 sh -c "echo stop > '$r/state'" || echo "WARN: stop $(cat "$r/name") failed"
    done
    sync
fi

echo "Starting kexec. Confirm in the new kernel with: sudo touch /run/razer-trial-ok"
if [ "${RAZER_KEXEC_FAST:-1}" = 1 ]; then
    exec systemctl kexec --force
fi
exec systemctl kexec
