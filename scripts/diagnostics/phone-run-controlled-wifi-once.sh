#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root" >&2
	exit 1
fi

modules=/etc/modules-load.d/razer-aura.conf
backup=/etc/modules-load.d/razer-aura.conf.before-controlled-wifi
blacklist=/etc/modprobe.d/razer-controlled-wifi.conf

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

echo "=== precondition ==="
date -Is
uname -a
lsmod | grep -E 'qcom_q6v5_mss|ath10k' || true
systemctl is-active rmtfs.service 2>/dev/null || true

if lsmod | grep -q '^qcom_q6v5_mss '; then
	echo "MSS_ALREADY_LOADED; refusing to claim a cold controlled start" >&2
	exit 2
fi

if [ -e "$backup" ]; then
	cp -f "$backup" "$modules"
fi
rm -f "$blacklist"
depmod -a

dmesg -C

systemctl start qrtr-ns.service 2>/dev/null || true
systemctl start tqftpserv.service 2>/dev/null || true

modprobe qcom_q6v5_mss
sleep 1

MSS="$(find_mss)"
echo disabled > "$MSS/recovery"
echo "MSS=$MSS"
echo "state-before=$(cat "$MSS/state")"

systemctl reset-failed rmtfs.service 2>/dev/null || true
systemctl start rmtfs.service

sleep 2
modprobe ath10k_core
modprobe ath10k_snoc

i=1
while [ "$i" -le 12 ]; do
	echo "=== poll $i ==="
	echo "state=$(cat "$MSS/state" 2>/dev/null || true)"
	ip -br link
	ls -la /sys/class/ieee80211 2>/dev/null || true
	qrtr-lookup 2>/dev/null |
		grep -E '(^ *69|WLFW|wlan|Service|  *66|  *43|  *14|  *49|  *64|4096)' ||
		true
	sleep 5
	i=$((i + 1))
done

systemctl enable rmtfs.service

echo "=== bluetooth ==="
for r in /sys/class/rfkill/rfkill*; do
	[ -e "$r" ] || continue
	printf '%s type=' "$(cat "$r/name" 2>/dev/null || true)"
	cat "$r/type" "$r/state" "$r/soft" "$r/hard" 2>/dev/null |
		tr '\n' ' '
	echo
done
ls -l /sys/class/bluetooth 2>/dev/null || true

echo "=== final dmesg ==="
dmesg --time-format=iso
