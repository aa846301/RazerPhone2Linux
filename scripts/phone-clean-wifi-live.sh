#!/usr/bin/env bash
set -u

systemctl stop rmtfs.service 2>/dev/null || true
pkill -x rmtfs-razer-test 2>/dev/null || true
pkill -x pd-mapper-live 2>/dev/null || true

for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    if [ "$(cat "$r/name" 2>/dev/null)" = "4080000.remoteproc" ]; then
        echo disabled > "$r/recovery" 2>/dev/null || true
        echo stop > "$r/state" 2>/dev/null || true
    fi
done

modprobe -r ath10k_snoc ath10k_core ath 2>/dev/null || true
modprobe -r qcom_q6v5_mss 2>/dev/null || true
modprobe -r qcom_pd_mapper 2>/dev/null || true

lsmod | egrep 'qcom_q6v5_mss|qcom_pd_mapper|ath10k' || true
