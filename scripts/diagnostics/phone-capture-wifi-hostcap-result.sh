#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root" >&2
	exit 1
fi

label="${1:-wifi-hostcap-result}"
out="/tmp/$label"
rm -rf "$out"
mkdir -p "$out"

uname -a > "$out/uname.txt"
cat /proc/cmdline > "$out/cmdline.txt"
dmesg --time-format=iso > "$out/dmesg.txt"
journalctl -b --no-pager > "$out/journal.txt"
journalctl -b -u tqftpserv -u rmtfs --no-pager > "$out/tqftpserv-rmtfs.txt"
qrtr-lookup > "$out/qrtr-lookup.txt" 2>&1 || true
ip -br link > "$out/ip-link.txt"
ls -la /sys/class/ieee80211 > "$out/ieee80211.txt" 2>&1 || true
nmcli device status > "$out/nmcli-device.txt" 2>&1 || true
nmcli -f IN-USE,SSID,BSSID,SIGNAL,SECURITY device wifi list \
	ifname wlan0 --rescan yes > "$out/nmcli-scan.txt" 2>&1 || true
lsmod > "$out/lsmod.txt"
modinfo ath10k_snoc > "$out/ath10k-snoc-modinfo.txt"
cat /sys/module/ath10k_snoc/parameters/force_skip_host_cap \
	> "$out/force-skip-host-cap.txt"
sha256sum "$(modinfo -n ath10k_snoc)" \
	> "$out/ath10k-snoc-sha256.txt"
systemctl --no-pager --full status tqftpserv rmtfs NetworkManager \
	> "$out/services.txt" 2>&1 || true

tar -C /tmp -czf "$out.tar.gz" "$label"
echo "$out.tar.gz"
