#!/usr/bin/env bash
set -euo pipefail

rel="$(uname -r)"
mod="/lib/modules/$rel/kernel/drivers/soc/qcom/qcom_pd_mapper.ko"

echo "kernel release: $rel"

systemctl stop rmtfs.service 2>/dev/null || true
pkill -x rmtfs-razer-test 2>/dev/null || true
pkill -x pd-mapper-live 2>/dev/null || true

if [ -e "$mod.disabled" ]; then
    echo "restoring kernel qcom_pd_mapper module:"
    echo "  $mod.disabled -> $mod"
    mv "$mod.disabled" "$mod"
elif [ -e "$mod" ]; then
    echo "kernel qcom_pd_mapper is already restored"
else
    echo "no qcom_pd_mapper module or disabled backup found at $mod"
fi

depmod -a "$rel"
ls -l "$mod"* 2>/dev/null || true

if [ "${NO_REBOOT:-0}" = "1" ]; then
    modprobe qcom_pd_mapper
    echo "kernel qcom_pd_mapper restored and loaded without reboot"
    exit 0
fi

echo "rebooting after restore"
reboot
