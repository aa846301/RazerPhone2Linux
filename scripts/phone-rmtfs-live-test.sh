#!/usr/bin/env bash
set -euo pipefail

TEST_RMTFS="${1:-/tmp/rmtfs-razer-test}"
OUT_LOG="${2:-/tmp/codex-rmtfs-live-test.log}"
RMTFS_LOG="${3:-/tmp/rmtfs-live-test.log}"
TEST_LABEL="${4:-$(basename "$TEST_RMTFS")}"

exec > >(tee "$OUT_LOG") 2>&1

echo "=== rmtfs live test: $TEST_LABEL ==="
date -Is
uname -a

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root"
    exit 1
fi

if [ ! -x "$TEST_RMTFS" ]; then
    echo "ERROR: missing executable test rmtfs: $TEST_RMTFS"
    exit 1
fi

echo "=== test binary ==="
ls -l "$TEST_RMTFS"
sha256sum "$TEST_RMTFS" || true
ldd "$TEST_RMTFS" || true

find_mss_rproc() {
    for rp in /sys/class/remoteproc/remoteproc*; do
        [ -e "$rp/name" ] || continue
        if grep -q '4080000.remoteproc' "$rp/name"; then
            printf '%s\n' "$rp"
            return 0
        fi
    done
    return 1
}

echo "=== stop managed rmtfs and clean direct rmtfs processes ==="
systemctl stop rmtfs.service rmtfs-razer-test.service 2>/dev/null || true
pkill -x rmtfs 2>/dev/null || true
pkill -x rmtfs-razer-test 2>/dev/null || true
pkill -x rmtfs-razer-fs12-swap 2>/dev/null || true
sleep 1

echo "=== ensure required services/modules ==="
systemctl start pd-mapper.service 2>/dev/null || true
systemctl start qrtr-ns.service 2>/dev/null || true
systemctl start tqftpserv.service 2>/dev/null || true
modprobe qcom_sysmon || true
modprobe qcom_q6v5_mss || true
modprobe ath10k_snoc || true

MSS_RPROC=""
for _ in $(seq 1 20); do
    MSS_RPROC="$(find_mss_rproc || true)"
    [ -n "$MSS_RPROC" ] && break
    sleep 0.5
done

if [ -z "$MSS_RPROC" ]; then
    echo "ERROR: MSS remoteproc 4080000.remoteproc not found"
    ls -l /sys/class/remoteproc || true
    exit 1
fi

echo "MSS_RPROC=$MSS_RPROC"
cat "$MSS_RPROC/name"
cat "$MSS_RPROC/state"

echo disabled > "$MSS_RPROC/recovery" 2>/dev/null || true

echo "=== start direct rmtfs ==="
rm -f "$RMTFS_LOG"
"$TEST_RMTFS" -r -P -s -v >"$RMTFS_LOG" 2>&1 &
RMTFS_PID=$!
echo "RMTFS_PID=$RMTFS_PID"
sleep 1
ps -p "$RMTFS_PID" -o pid,stat,comm,args || true

echo "=== start MSS ==="
if grep -q '^offline$' "$MSS_RPROC/state"; then
    echo start > "$MSS_RPROC/state"
elif grep -q '^crashed$' "$MSS_RPROC/state"; then
    echo "MSS already crashed before start request"
else
    cat "$MSS_RPROC/state"
fi

echo "=== poll MSS/QRTR/WiFi ==="
for i in $(seq 1 80); do
    state="$(cat "$MSS_RPROC/state" 2>/dev/null || echo missing)"
    printf '[%02d] state=%s ' "$i" "$state"
    if command -v qrtr-lookup >/dev/null 2>&1; then
        qrtr-lookup 2>/dev/null | tr '\n' ';' | sed 's/;$/\n/'
    else
        echo
    fi
    if [ "$state" = "crashed" ]; then
        break
    fi
    if ls /sys/class/ieee80211/* >/dev/null 2>&1; then
        echo "WiFi phy appeared"
        break
    fi
    sleep 0.5
done

echo "=== remoteproc summary ==="
cat "$MSS_RPROC/name" || true
cat "$MSS_RPROC/state" || true
cat "$MSS_RPROC/recovery" || true
cat "$MSS_RPROC/coredump" 2>/dev/null || true

echo "=== rmtfs log tail ==="
tail -160 "$RMTFS_LOG" || true

echo "=== tqftpserv journal ==="
journalctl -u tqftpserv -b --no-pager | tail -120 || true

echo "=== dmesg relevant tail ==="
dmesg --time-format=iso | grep -Ei 'remoteproc|q6v5|mpss|modem|fatal|rmtfs|qrtr|pd.mapper|pdr|servreg|wlfw|ath10k|tftp|qmi|smem' | tail -180 || true

echo "=== wifi interfaces ==="
ip link || true
ls -l /sys/class/ieee80211 2>/dev/null || true

echo "=== done ==="
date -Is
