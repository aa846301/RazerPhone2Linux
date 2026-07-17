#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/tmp/razer-wifi-diag-f3-two-phase-$(date +%Y%m%d-%H%M%S)"
DIAG_ROUTER="${DIAG_ROUTER:-/tmp/diag-router}"
DIAG_CAPTURE="${DIAG_CAPTURE:-/tmp/diag-capture}"
RMTFS="${RMTFS:-/usr/local/bin/rmtfs-razer-test}"
CAPTURE_SECONDS="${CAPTURE_SECONDS:-18}"
mkdir -p "$LOG_DIR"

exec > >(tee "$LOG_DIR/test.log") 2>&1

find_mss() {
    for r in /sys/class/remoteproc/remoteproc*; do
        [ -e "$r/name" ] || continue
        if [ "$(cat "$r/name" 2>/dev/null || true)" = "4080000.remoteproc" ]; then
            echo "$r"
            return 0
        fi
    done
    return 1
}

echo "=== diag-router two-phase F3/MSS capture ==="
date -Is
uname -a

for bin in "$DIAG_ROUTER" "$DIAG_CAPTURE" "$RMTFS"; do
    [ -x "$bin" ] || { echo "missing executable: $bin"; exit 2; }
done

echo "=== cleanup ==="
systemctl stop rmtfs.service 2>/dev/null || true
systemctl stop tqftpserv.service 2>/dev/null || true
systemctl stop pd-mapper.service 2>/dev/null || true
pkill -f "$DIAG_CAPTURE" 2>/dev/null || true
pkill -f "$DIAG_ROUTER" 2>/dev/null || true
pkill -f rmtfs-razer-test 2>/dev/null || true
if MSS="$(find_mss)"; then
    echo disabled > "$MSS/recovery" 2>/dev/null || true
    echo stop > "$MSS/state" 2>/dev/null || true
fi
modprobe -r ath10k_snoc ath10k_core ath 2>/dev/null || true
modprobe -r qcom_q6v5_mss 2>/dev/null || true
sleep 1

echo "=== start diag-router before Qualcomm userspace services ==="
"$DIAG_ROUTER" > "$LOG_DIR/diag-router.log" 2>&1 &
DIAG_PID="$!"
echo "$DIAG_PID" > "$LOG_DIR/diag-router.pid"
sleep 2
ps -fp "$DIAG_PID" || true

echo "=== start Qualcomm userspace services after diag-router ==="
systemctl start qrtr-ns.service 2>/dev/null || true
systemctl start pd-mapper.service 2>/dev/null || true
systemctl start tqftpserv.service 2>/dev/null || true

echo "=== phase 1: send broad masks, tolerate reset ==="
"$DIAG_CAPTURE" -d 3 > "$LOG_DIR/diag-mask.log" 2>&1 || true
cat "$LOG_DIR/diag-mask.log" || true

echo "=== phase 2: passive capture before MSS ==="
"$DIAG_CAPTURE" -n -d "$CAPTURE_SECONDS" > "$LOG_DIR/diag-passive.log" 2>&1 &
CAPTURE_PID="$!"
echo "$CAPTURE_PID" > "$LOG_DIR/diag-passive.pid"
sleep 1
ps -fp "$CAPTURE_PID" || true

echo "=== start MSS/rmtfs ==="
modprobe qcom_q6v5_mss
sleep 1
if MSS="$(find_mss)"; then
    echo "MSS=$MSS"
    echo disabled > "$MSS/recovery" 2>/dev/null || true
    printf "state before rmtfs="
    cat "$MSS/state" 2>/dev/null || true
fi

"$RMTFS" -r -P -s -v > "$LOG_DIR/rmtfs.log" 2>&1 &
RMTFS_PID="$!"
echo "$RMTFS_PID" > "$LOG_DIR/rmtfs.pid"

for i in $(seq 1 "$CAPTURE_SECONDS"); do
    echo "--- sample $i ---"
    if MSS="$(find_mss)"; then
        printf "mss_state="
        cat "$MSS/state" 2>/dev/null || true
    fi
    timeout 2 qrtr-lookup 2>&1 | tee "$LOG_DIR/qrtr-$i.log" || true
    sleep 1
done

wait "$CAPTURE_PID" || true

echo "=== diag passive interesting strings ==="
grep -aEi 'fatal|error|assert|crash|wdog|watchdog|mss|modem|wlan|wcn|qmi|rfs|efs|nv|pddump|servreg|timeout|file|line' \
    "$LOG_DIR/diag-passive.log" || true

echo "=== rmtfs tail ==="
tail -220 "$LOG_DIR/rmtfs.log" || true

echo "=== dmesg filtered ==="
dmesg --time-format=iso |
    egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|rmtfs|glink|firmware|diag|dog|pddump|smem|rmb' |
    tail -260 | tee "$LOG_DIR/dmesg-filtered.log" || true

tar -C /tmp -czf "$LOG_DIR.tar.gz" "$(basename "$LOG_DIR")"
echo "LOG_DIR=$LOG_DIR"
echo "TAR=$LOG_DIR.tar.gz"
