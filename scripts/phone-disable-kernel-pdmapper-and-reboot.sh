#!/usr/bin/env bash
set -euo pipefail

rel="$(uname -r)"
mod="/lib/modules/$rel/kernel/drivers/soc/qcom/qcom_pd_mapper.ko"

echo "kernel release: $rel"

systemctl stop rmtfs.service 2>/dev/null || true
pkill -x rmtfs-razer-test 2>/dev/null || true
pkill -x pd-mapper-live 2>/dev/null || true

if [ -e "$mod" ]; then
    if [ ! -e "$mod.disabled" ]; then
        echo "disabling kernel qcom_pd_mapper module:"
        echo "  $mod -> $mod.disabled"
        mv "$mod" "$mod.disabled"
    else
        echo "kernel qcom_pd_mapper is already disabled"
    fi
else
    echo "kernel qcom_pd_mapper module is not present at $mod"
fi

depmod -a "$rel"
ls -l "$mod"* 2>/dev/null || true

echo "rebooting for a clean userspace-pdmapper test"
reboot
