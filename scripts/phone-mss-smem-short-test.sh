#!/bin/sh
set -eu

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

echo "=== short MSS SMEM crash test ==="
date -Is
uname -a

systemctl stop rmtfs.service 2>/dev/null || true
modprobe -r ath10k_snoc ath10k_core ath 2>/dev/null || true
modprobe qcom_q6v5_mss

MSS="$(find_mss)"
echo disabled > "$MSS/recovery" 2>/dev/null || true
systemctl reset-failed rmtfs.service 2>/dev/null || true
systemctl restart rmtfs.service

sleep 5

echo "=== state ==="
cat "$MSS/name" "$MSS/state" "$MSS/recovery" 2>/dev/null || true
qrtr-lookup 2>/dev/null | grep -E 'Service|(^ *14|^ *43|^ *64|^ *66|^ *69|4096|WLFW|wlan)' || true

echo "=== crash lines ==="
dmesg --time-format=iso |
    egrep -i 'q6v5 diag (fatal|watchdog): smem|fatal error without message|crash detected|remote processor 4080000.remoteproc is now up|PDM diag: lookup request node=0|PDM diag: lookup response service=tms/pddump_disabled|Internal error|Oops' |
    tail -80

systemctl stop rmtfs.service 2>/dev/null || true
