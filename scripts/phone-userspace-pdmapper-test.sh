#!/usr/bin/env bash
set -u

LOG_DIR="/tmp/razer-userspace-pdmapper-$(date +%Y%m%d-%H%M%S)"
PDMAPPER="${PDMAPPER:-/tmp/pd-mapper-live}"
RMTFS="${RMTFS:-/usr/local/bin/rmtfs-razer-test}"
mkdir -p "$LOG_DIR"

exec > >(tee "$LOG_DIR/test.log") 2>&1

echo "=== userspace pd-mapper MSS test ==="
date -Is
uname -a

if [ ! -x "$PDMAPPER" ]; then
    echo "missing executable: $PDMAPPER"
    exit 2
fi

if [ ! -x "$RMTFS" ]; then
    echo "missing executable: $RMTFS"
    exit 2
fi

echo "=== baseline ==="
systemctl --no-pager --plain is-active qrtr-ns tqftpserv rmtfs 2>/dev/null || true
lsmod | egrep 'qcom_pd_mapper|qcom_q6v5_mss|qcom_sysmon|qrtr|ath10k' || true
qrtr-lookup 2>&1 || true

echo "=== cleanup old WiFi/MSS state ==="
systemctl stop rmtfs.service 2>/dev/null || true
pkill -f rmtfs-razer-test 2>/dev/null || true
pkill -x "$(basename "$PDMAPPER")" 2>/dev/null || true

for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    name="$(cat "$r/name" 2>/dev/null || true)"
    if [ "$name" = "4080000.remoteproc" ]; then
        echo "MSS remoteproc=$r"
        echo disabled > "$r/recovery" 2>/dev/null || true
        cat "$r/state" 2>/dev/null || true
    fi
done

modprobe -r ath10k_snoc ath10k_core ath 2>/dev/null || true
modprobe -r qcom_q6v5_mss 2>/dev/null || true

echo "=== switch from kernel qcom_pd_mapper to userspace pd-mapper ==="
mkdir -p /run/modprobe.d
cat > /run/modprobe.d/razer-no-kernel-pdmapper.conf <<'EOF'
install qcom_pd_mapper /bin/false
EOF
modprobe -r qcom_pd_mapper 2>/dev/null || true
lsmod | egrep 'qcom_pd_mapper|qcom_q6v5_mss|qcom_sysmon|qrtr|ath10k' || true

systemctl start qrtr-ns.service 2>/dev/null || true
systemctl start tqftpserv.service 2>/dev/null || true

"$PDMAPPER" > "$LOG_DIR/pd-mapper.log" 2>&1 &
PDM_PID="$!"
echo "$PDM_PID" > "$LOG_DIR/pd-mapper.pid"
sleep 2
ps -fp "$PDM_PID" || true
qrtr-lookup 2>&1 | tee "$LOG_DIR/qrtr-before-mss.log" || true

echo "=== load MSS and start rmtfs ==="
modprobe qcom_q6v5_mss
sleep 1
if lsmod | grep -q '^qcom_pd_mapper '; then
    echo "kernel qcom_pd_mapper reloaded; removing before MSS power-up"
    modprobe -r qcom_pd_mapper 2>/dev/null || true
fi
if lsmod | grep -q '^qcom_pd_mapper '; then
    echo "kernel qcom_pd_mapper still loaded; aborting userspace-only test"
    lsmod | egrep 'qcom_pd_mapper|qcom_q6v5_mss|qcom_sysmon|qrtr|ath10k|pdr|qmi' || true
    exit 3
fi
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    name="$(cat "$r/name" 2>/dev/null || true)"
    if [ "$name" = "4080000.remoteproc" ]; then
        echo disabled > "$r/recovery" 2>/dev/null || true
        cat "$r/state" 2>/dev/null || true
    fi
done

"$RMTFS" -r -P -s -v > "$LOG_DIR/rmtfs.log" 2>&1 &
RMTFS_PID="$!"
echo "$RMTFS_PID" > "$LOG_DIR/rmtfs.pid"

for i in $(seq 1 15); do
    echo "--- sample $i ---"
    qrtr-lookup 2>&1 | tee "$LOG_DIR/qrtr-$i.log" || true
    ls -la /sys/class/ieee80211 2>/dev/null || true
    ip link show 2>/dev/null | grep -E 'wlan|usb|lo:' || true
    sleep 1
done

echo "=== if WLFW appeared, try ath10k once ==="
if qrtr-lookup 2>/dev/null | awk '$1 == 69 { found = 1 } END { exit(found ? 0 : 1) }'; then
    modprobe ath10k_core || true
    modprobe ath10k_snoc || true
    sleep 3
    ls -la /sys/class/ieee80211 2>/dev/null || true
    ip link show 2>/dev/null | grep -E 'wlan|usb|lo:' || true
fi

echo "=== final remoteproc state ==="
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    printf '%s name=' "$r"; cat "$r/name" 2>/dev/null || true
    printf '%s state=' "$r"; cat "$r/state" 2>/dev/null || true
done

echo "=== filtered dmesg ==="
dmesg --time-format=iso |
    egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|pd-mapper|rmtfs|glink|firmware|dog|PDM diag' |
    tail -260 | tee "$LOG_DIR/dmesg-filtered.log" || true

echo "=== userspace pd-mapper log ==="
tail -220 "$LOG_DIR/pd-mapper.log" || true

echo "=== rmtfs log ==="
tail -260 "$LOG_DIR/rmtfs.log" || true

echo "=== stop rmtfs after controlled sample ==="
kill "$RMTFS_PID" 2>/dev/null || true
systemctl stop rmtfs.service 2>/dev/null || true

echo "LOG_DIR=$LOG_DIR"
