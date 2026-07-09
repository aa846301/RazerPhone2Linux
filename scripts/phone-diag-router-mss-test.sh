#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/tmp/razer-wifi-diag-router-$(date +%Y%m%d-%H%M%S)"
DIAG_ROUTER="${DIAG_ROUTER:-/tmp/diag-router}"
PDMAPPER="${PDMAPPER:-/tmp/pd-mapper-live}"
RMTFS="${RMTFS:-/usr/local/bin/rmtfs-razer-test}"
mkdir -p "$LOG_DIR"

exec > >(tee "$LOG_DIR/test.log") 2>&1

echo "=== diag-router MSS test ==="
date -Is
uname -a

if [ ! -x "$DIAG_ROUTER" ]; then
    echo "missing executable: $DIAG_ROUTER"
    exit 2
fi

if [ ! -x "$RMTFS" ]; then
    echo "missing executable: $RMTFS"
    exit 2
fi

if [ ! -x "$PDMAPPER" ]; then
    echo "missing executable: $PDMAPPER"
    exit 2
fi

echo "=== cleanup old WiFi/MSS processes ==="
systemctl stop --no-block rmtfs.service 2>/dev/null || true
systemctl stop --no-block tqftpserv.service 2>/dev/null || true
systemctl stop --no-block pd-mapper.service 2>/dev/null || true
pkill -x "$(basename "$DIAG_ROUTER")" 2>/dev/null || true
pkill -x "$(basename "$PDMAPPER")" 2>/dev/null || true
pkill -x rmtfs-razer-test 2>/dev/null || true

MSS_STATE=""
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    name="$(cat "$r/name" 2>/dev/null || true)"
    if [ "$name" = "4080000.remoteproc" ]; then
        echo disabled > "$r/recovery" 2>/dev/null || true
        MSS_STATE="$(cat "$r/state" 2>/dev/null || true)"
        echo "MSS state=$MSS_STATE"
    fi
done

# Unloading ath10k_snoc after MSS has already crashed can block forever in
# device-release on this port. It is not part of the ordering variable here.
lsmod | grep -E '^ath10k_(snoc|core) ' || true
if [ "$MSS_STATE" != "offline" ]; then
    echo "MSS must be offline before this ordering test."
    echo "Disable rmtfs.service, reboot, and run the test before MSS is powered."
    exit 4
fi

echo "=== disable kernel pd-mapper for this live test ==="
mkdir -p /run/modprobe.d
cat > /run/modprobe.d/razer-no-kernel-pdmapper.conf <<'EOF'
install qcom_pd_mapper /bin/false
EOF
modprobe -r qcom_pd_mapper 2>/dev/null || true
if lsmod | grep -q '^qcom_pd_mapper '; then
    echo "kernel qcom_pd_mapper is still loaded; aborting"
    exit 3
fi

echo "=== start diag-router before Qualcomm userspace services ==="
"$DIAG_ROUTER" > "$LOG_DIR/diag-router.log" 2>&1 &
DIAG_PID="$!"
echo "$DIAG_PID" > "$LOG_DIR/diag-router.pid"
sleep 2
ps -fp "$DIAG_PID" || true

echo "=== start Qualcomm userspace services after diag-router ==="
# QRTR is provided by the kernel and qrtr-ns may be socket/dbus activated.
# Keep the explicit start for Ubuntu, but diag-router is already listening.
systemctl start qrtr-ns.service 2>/dev/null || true
"$PDMAPPER" > "$LOG_DIR/pd-mapper.log" 2>&1 &
PDM_PID="$!"
echo "$PDM_PID" > "$LOG_DIR/pd-mapper.pid"
sleep 2
ps -fp "$PDM_PID" || true
systemctl start tqftpserv.service 2>/dev/null || true
systemctl --no-pager --plain is-active \
    qrtr-ns pd-mapper tqftpserv rmtfs 2>/dev/null || true

echo "=== load MSS module, keep recovery disabled ==="
modprobe qcom_q6v5_mss
sleep 1
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    name="$(cat "$r/name" 2>/dev/null || true)"
    if [ "$name" = "4080000.remoteproc" ]; then
        echo "MSS remoteproc=$r"
        echo disabled > "$r/recovery" 2>/dev/null || true
        cat "$r/state" || true
    fi
done

echo "=== start rmtfs to power MSS ==="
"$RMTFS" -r -P -s -v > "$LOG_DIR/rmtfs.log" 2>&1 &
RMTFS_PID="$!"
echo "$RMTFS_PID" > "$LOG_DIR/rmtfs.pid"

for i in $(seq 1 12); do
    echo "--- sample $i ---"
    qrtr-lookup 2>&1 | tee "$LOG_DIR/qrtr-$i.log" || true
    ls -la /sys/class/ieee80211 2>/dev/null || true
    ip link show 2>/dev/null | grep -E 'wlan|usb|lo:' || true
    sleep 1
done

echo "=== if WLFW appeared, try ath10k once ==="
if qrtr-lookup 2>/dev/null | grep -qi 'wlfw\|69'; then
    modprobe ath10k_core || true
    modprobe ath10k_snoc || true
    sleep 3
fi

echo "=== final state ==="
systemctl --no-pager --plain is-active qrtr-ns tqftpserv rmtfs 2>/dev/null || true
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    printf '%s name=' "$r"; cat "$r/name" 2>/dev/null || true
    printf '%s state=' "$r"; cat "$r/state" 2>/dev/null || true
done

echo "=== filtered dmesg ==="
dmesg --time-format=iso |
    egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|rmtfs|glink|firmware|diag|dog' |
    tail -220 | tee "$LOG_DIR/dmesg-filtered.log" || true

echo "=== diag-router log ==="
tail -160 "$LOG_DIR/diag-router.log" || true

echo "=== rmtfs log ==="
tail -220 "$LOG_DIR/rmtfs.log" || true

echo "=== userspace pd-mapper log ==="
tail -220 "$LOG_DIR/pd-mapper.log" || true

echo "=== leave MSS frozen after controlled sample ==="
kill "$RMTFS_PID" 2>/dev/null || true
systemctl stop --no-block rmtfs.service 2>/dev/null || true
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    if [ "$(cat "$r/name" 2>/dev/null || true)" = "4080000.remoteproc" ]; then
        echo disabled > "$r/recovery" 2>/dev/null || true
    fi
done

echo "LOG_DIR=$LOG_DIR"
