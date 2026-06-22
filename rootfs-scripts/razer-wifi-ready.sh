#!/bin/sh
set -eu

# HelixScreen probes WiFi only during startup. On SDM845, MSS/WLFW and
# ath10k_snoc can need several seconds after multi-user startup, so wait for
# wlan0 before allowing HelixScreen to initialize its NetworkManager backend.
timeout="${RAZER_WIFI_READY_TIMEOUT:-75}"
elapsed=0

modprobe qcom_q6v5_mss 2>/dev/null || true
modprobe ath10k_core 2>/dev/null || true
modprobe ath10k_snoc 2>/dev/null || true

while [ "$elapsed" -lt "$timeout" ]; do
	if [ -d /sys/class/net/wlan0 ]; then
		nmcli radio wifi on 2>/dev/null || true
		echo "razer-wifi-ready: wlan0 available after ${elapsed}s"
		exit 0
	fi
	sleep 1
	elapsed=$((elapsed + 1))
done

echo "razer-wifi-ready: wlan0 not available after ${timeout}s; starting HelixScreen anyway" >&2
exit 0
