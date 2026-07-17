#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/tmp/razer-wifi-diag-f3-$(date +%Y%m%d-%H%M%S)"
DIAG_ROUTER="${DIAG_ROUTER:-/tmp/diag-router}"
DIAG_CAPTURE="${DIAG_CAPTURE:-/tmp/diag-capture}"
PDMAPPER="${PDMAPPER:-}"
RMTFS="${RMTFS:-/usr/local/bin/rmtfs-razer-test}"
CAPTURE_SECONDS="${CAPTURE_SECONDS:-25}"
mkdir -p "$LOG_DIR"

exec > >(tee "$LOG_DIR/test.log") 2>&1

echo "=== diag-router F3/MSS capture test ==="
date -Is
uname -a

need_exec() {
    if [ ! -x "$1" ]; then
        echo "missing executable: $1"
        exit 2
    fi
}

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

need_exec "$DIAG_ROUTER"
need_exec "$DIAG_CAPTURE"
need_exec "$RMTFS"
if [ -n "$PDMAPPER" ]; then
    need_exec "$PDMAPPER"
fi

echo "=== cleanup old processes/services ==="
systemctl stop --no-block rmtfs.service 2>/dev/null || true
systemctl stop --no-block tqftpserv.service 2>/dev/null || true
systemctl stop --no-block pd-mapper.service 2>/dev/null || true
pkill -x "$(basename "$DIAG_CAPTURE")" 2>/dev/null || true
pkill -x "$(basename "$DIAG_ROUTER")" 2>/dev/null || true
if [ -n "$PDMAPPER" ]; then
    pkill -x "$(basename "$PDMAPPER")" 2>/dev/null || true
fi
pkill -x rmtfs-razer-test 2>/dev/null || true
sleep 1

if MSS="$(find_mss)"; then
    echo "existing MSS=$MSS"
    echo disabled > "$MSS/recovery" 2>/dev/null || true
    MSS_STATE="$(cat "$MSS/state" 2>/dev/null || true)"
    echo "MSS state=$MSS_STATE"
    if [ "$MSS_STATE" != "offline" ]; then
        echo "MSS must be offline before DIAG capture."
        echo "Disable rmtfs.service, reboot, then rerun this script."
        exit 5
    fi
fi

echo "=== start diag-router before Qualcomm userspace services ==="
stdbuf -oL -eL "$DIAG_ROUTER" > "$LOG_DIR/diag-router.log" 2>&1 &
DIAG_PID="$!"
echo "$DIAG_PID" > "$LOG_DIR/diag-router.pid"
sleep 2
ps -fp "$DIAG_PID" || true
if ! kill -0 "$DIAG_PID" 2>/dev/null; then
    echo "diag-router exited before MSS start"
    cat "$LOG_DIR/diag-router.log" || true
    exit 3
fi

echo "=== start Qualcomm userspace services after DIAG is ready ==="
systemctl start qrtr-ns.service 2>/dev/null || true
if [ -n "$PDMAPPER" ]; then
    stdbuf -oL -eL "$PDMAPPER" > "$LOG_DIR/pd-mapper.log" 2>&1 &
    PDMAPPER_PID="$!"
    echo "$PDMAPPER_PID" > "$LOG_DIR/pd-mapper.pid"
    sleep 1
    if ! kill -0 "$PDMAPPER_PID" 2>/dev/null; then
        echo "userspace pd-mapper exited before MSS start"
        cat "$LOG_DIR/pd-mapper.log" || true
        exit 6
    fi
else
    echo "PDMAPPER is empty; using the kernel qcom_pd_mapper path"
fi
systemctl start tqftpserv.service 2>/dev/null || true
systemctl --no-pager --plain is-active \
    qrtr-ns pd-mapper tqftpserv rmtfs 2>/dev/null || true
timeout 3 qrtr-lookup 2>&1 | tee "$LOG_DIR/qrtr-before.log" || true
sleep 2

echo "=== attach DIAG/F3 mask before MSS start ==="
"$DIAG_CAPTURE" -F -d "$CAPTURE_SECONDS" > "$LOG_DIR/diag-capture.log" 2>&1 &
CAPTURE_PID="$!"
echo "$CAPTURE_PID" > "$LOG_DIR/diag-capture.pid"
sleep 2
ps -fp "$CAPTURE_PID" || true
tail -80 "$LOG_DIR/diag-capture.log" || true
if ! kill -0 "$CAPTURE_PID" 2>/dev/null; then
    echo "diag-capture exited before MSS start"
    cat "$LOG_DIR/diag-capture.log" || true
    exit 4
fi

echo "=== load MSS module, keep recovery disabled ==="
modprobe qcom_q6v5_mss
sleep 1
if MSS="$(find_mss)"; then
    echo "MSS remoteproc=$MSS"
    echo disabled > "$MSS/recovery" 2>/dev/null || true
    printf 'state before rmtfs='
    cat "$MSS/state" || true
else
    echo "MSS remoteproc not found after module load"
fi

echo "=== start rmtfs to power MSS ==="
"$RMTFS" -r -P -s -v > "$LOG_DIR/rmtfs.log" 2>&1 &
RMTFS_PID="$!"
echo "$RMTFS_PID" > "$LOG_DIR/rmtfs.pid"

for i in $(seq 1 "$CAPTURE_SECONDS"); do
    echo "--- sample $i ---"
    if MSS="$(find_mss)"; then
        printf 'mss_state='
        cat "$MSS/state" || true
    fi
    timeout 3 qrtr-lookup 2>&1 | tee "$LOG_DIR/qrtr-$i.log" || true
    ls -la /sys/class/ieee80211 2>/dev/null || true
    ip link show 2>/dev/null | grep -E 'wlan|usb|lo:' || true
    sleep 1
done

wait "$CAPTURE_PID" || true

echo "=== final state ==="
systemctl --no-pager --plain is-active qrtr-ns pd-mapper tqftpserv rmtfs 2>/dev/null || true
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    printf '%s name=' "$r"; cat "$r/name" 2>/dev/null || true
    printf '%s state=' "$r"; cat "$r/state" 2>/dev/null || true
done

echo "=== filtered dmesg ==="
dmesg --time-format=iso |
    egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|rmtfs|glink|firmware|diag|dog|pddump' |
    tail -260 | tee "$LOG_DIR/dmesg-filtered.log" || true

echo "=== diag-capture interesting strings ==="
grep -aEi 'fatal|error|assert|crash|wdog|watchdog|mss|modem|wlan|wcn|qmi|rfs|efs|nv|pddump|servreg|timeout' \
    "$LOG_DIR/diag-capture.log" || true

echo "=== diag-router log ==="
tail -180 "$LOG_DIR/diag-router.log" || true

if [ -f "$LOG_DIR/pd-mapper.log" ]; then
    echo "=== userspace pd-mapper log ==="
    tail -180 "$LOG_DIR/pd-mapper.log" || true
fi

echo "=== rmtfs log ==="
tail -240 "$LOG_DIR/rmtfs.log" || true

echo "=== leave MSS frozen after controlled capture ==="
kill "$RMTFS_PID" 2>/dev/null || true
systemctl stop --no-block rmtfs.service 2>/dev/null || true
if MSS="$(find_mss)"; then
    echo disabled > "$MSS/recovery" 2>/dev/null || true
fi
kill "$DIAG_PID" 2>/dev/null || true
if [ -n "${PDMAPPER_PID:-}" ]; then
    kill "$PDMAPPER_PID" 2>/dev/null || true
fi

tar -C /tmp -czf "$LOG_DIR.tar.gz" "$(basename "$LOG_DIR")"
echo "LOG_DIR=$LOG_DIR"
echo "TAR=$LOG_DIR.tar.gz"
