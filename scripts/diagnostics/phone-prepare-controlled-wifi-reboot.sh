#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root" >&2
	exit 1
fi

modules=/etc/modules-load.d/razer-aura.conf
backup=/etc/modules-load.d/razer-aura.conf.before-controlled-wifi
blacklist=/etc/modprobe.d/razer-controlled-wifi.conf

if [ ! -e "$backup" ]; then
	cp -f "$modules" "$backup"
fi

grep -v -E '^(qcom_q6v5_mss|ath10k_core|ath10k_snoc)$' \
	"$backup" > "$modules"

cat > "$blacklist" <<'EOF'
blacklist qcom_q6v5_mss
blacklist ath10k_core
blacklist ath10k_snoc
EOF

systemctl disable rmtfs.service
sync
echo "CONTROLLED_WIFI_BOOT_PREPARED"
reboot
