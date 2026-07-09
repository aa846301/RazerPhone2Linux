#!/bin/sh
set -eu

OUT_BASE="${1:-/tmp/mss-crash-evidence}"
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
OUT="$OUT_BASE-$STAMP"
mkdir -p "$OUT"

log()
{
    printf '%s\n' "$*" | tee -a "$OUT/run.log"
}

save_cmd()
{
    name="$1"
    shift
    {
        echo "### $*"
        "$@" 2>&1 || true
    } > "$OUT/$name" 2>&1
}

copy_if_exists()
{
    src="$1"
    dst="$2"
    if [ -e "$src" ]; then
        cat "$src" > "$OUT/$dst" 2>&1 || true
    fi
}

find_mss()
{
    for r in /sys/class/remoteproc/remoteproc*; do
        [ -e "$r/name" ] || continue
        if [ "$(cat "$r/name" 2>/dev/null || true)" = "4080000.remoteproc" ]; then
            echo "$r"
            return 0
        fi
    done
    return 1
}

snapshot_remoteproc()
{
    tag="$1"
    {
        echo "### remoteproc sysfs ($tag)"
        for r in /sys/class/remoteproc/remoteproc*; do
            [ -e "$r/name" ] || continue
            echo "--- $r"
            for f in name state recovery coredump firmware; do
                [ -e "$r/$f" ] && printf '%s=' "$f" && cat "$r/$f" 2>/dev/null || true
            done
            ls -la "$r" 2>/dev/null || true
        done
        echo
        echo "### remoteproc debugfs ($tag)"
        for d in /sys/kernel/debug/remoteproc/remoteproc*; do
            [ -d "$d" ] || continue
            echo "--- $d"
            ls -la "$d" 2>/dev/null || true
            for f in "$d"/trace* "$d"/carveouts "$d"/resource_table; do
                [ -e "$f" ] || continue
                echo "--- file: $f"
                case "$f" in
                    */resource_table)
                        hexdump -C "$f" 2>/dev/null | head -200 || true
                        ;;
                    *)
                        cat "$f" 2>/dev/null || true
                        ;;
                esac
                echo
            done
        done
    } > "$OUT/remoteproc-$tag.txt" 2>&1
}

snapshot_devcoredump()
{
    tag="$1"
    {
        echo "### devcoredump ($tag)"
        for d in /sys/class/devcoredump/devcd*; do
            [ -d "$d" ] || continue
            echo "--- $d"
            ls -la "$d" 2>/dev/null || true
            for f in "$d"/device "$d"/failing_device "$d"/modalias; do
                [ -e "$f" ] && echo "--- $f" && cat "$f" 2>/dev/null || true
            done
            if [ -r "$d/data" ]; then
                dump="$OUT/$(basename "$d")-$tag-first16m.bin"
                echo "--- saving first 16 MiB from $d/data to $dump"
                dd if="$d/data" of="$dump" bs=1M count=16 2>/dev/null || true
                strings "$dump" > "$dump.strings" 2>/dev/null || true
            fi
        done
    } > "$OUT/devcoredump-$tag.txt" 2>&1
}

snapshot_qrtr_loop()
{
    {
        i=0
        while [ "$i" -lt 40 ]; do
            echo "--- qrtr poll $i $(date -Is 2>/dev/null || true)"
            qrtr-lookup 2>&1 | grep -E 'Service|(^ *14|^ *43|^ *64|^ *66|^ *69|4096|WLFW|wlan|modem)' || true
            i=$((i + 1))
            sleep 0.2
        done
    } > "$OUT/qrtr-window.txt" 2>&1 &
    echo $!
}

log "MSS crash evidence output: $OUT"

mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
mount -t pstore none /sys/fs/pstore 2>/dev/null || true

save_cmd uname.txt uname -a
save_cmd cmdline.txt cat /proc/cmdline
save_cmd modules-before.txt lsmod
save_cmd services-before.txt systemctl --no-pager --plain status rmtfs qrtr-ns tqftpserv NetworkManager helixscreen
save_cmd pstore-list-before.txt ls -la /sys/fs/pstore
save_cmd devcoredump-list-before.txt ls -la /sys/class/devcoredump
save_cmd qrtr-before.txt qrtr-lookup
save_cmd dmesg-before.txt dmesg --time-format=iso
snapshot_remoteproc before
snapshot_devcoredump before

log "Stopping WiFi/MSS userspace and modules..."
systemctl stop rmtfs.service 2>/dev/null || true
modprobe -r ath10k_snoc ath10k_core ath 2>/dev/null || true
systemctl start pd-mapper.service 2>/dev/null || true
modprobe qcom_q6v5_mss 2>/dev/null || true
modprobe qcom_sysmon 2>/dev/null || true

MSS="$(find_mss || true)"
if [ -z "$MSS" ]; then
    log "ERROR: MSS remoteproc not found"
    exit 3
fi

log "Using MSS remoteproc: $MSS"

echo disabled > "$MSS/recovery" 2>/dev/null || true
if [ -e "$MSS/coredump" ]; then
    echo enabled > "$MSS/coredump" 2>/dev/null || echo default > "$MSS/coredump" 2>/dev/null || true
fi

if [ -w /sys/kernel/debug/dynamic_debug/control ]; then
    {
        echo 'file drivers/remoteproc/qcom_q6v5_mss.c +p'
        echo 'file drivers/remoteproc/qcom_q6v5.c +p'
        echo 'file drivers/remoteproc/remoteproc_core.c +p'
        echo 'file drivers/soc/qcom/qcom_pd_mapper.c +p'
        echo 'file net/qrtr/* +p'
    } > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
fi

echo "=== codex MSS evidence trigger $(date -Is 2>/dev/null || true) ===" > /dev/kmsg 2>/dev/null || true

QPID="$(snapshot_qrtr_loop)"
log "Starting rmtfs to power MSS..."
systemctl reset-failed rmtfs.service 2>/dev/null || true
systemctl restart rmtfs.service 2>/dev/null || true

sleep 10
wait "$QPID" 2>/dev/null || true

snapshot_remoteproc after
snapshot_devcoredump after
save_cmd pstore-list-after.txt ls -la /sys/fs/pstore
save_cmd pstore-after.txt sh -c 'for f in /sys/fs/pstore/*; do [ -e "$f" ] && echo "--- $f" && cat "$f"; done'
save_cmd qrtr-after.txt qrtr-lookup
save_cmd modules-after.txt lsmod
save_cmd services-after.txt systemctl --no-pager --plain status rmtfs qrtr-ns tqftpserv NetworkManager helixscreen
save_cmd rmtfs-journal.txt journalctl -u rmtfs -b --no-pager
save_cmd tqftpserv-journal.txt journalctl -u tqftpserv -b --no-pager
save_cmd dmesg-after.txt dmesg --time-format=iso
save_cmd dmesg-mss-focused.txt sh -c "dmesg --time-format=iso | egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|panic|watchdog|dog|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|rmtfs|glink|firmware|smem|rmb|aoss|pdc|sysmon' | tail -400"

tarball="$OUT.tar.gz"
tar -C "$(dirname "$OUT")" -czf "$tarball" "$(basename "$OUT")" 2>/dev/null || true

log "Evidence complete:"
log "  directory: $OUT"
log "  tarball:   $tarball"
log "Key files:"
log "  dmesg-mss-focused.txt"
log "  remoteproc-after.txt"
log "  devcoredump-after.txt"
log "  qrtr-window.txt"
log "  rmtfs-journal.txt"
