#!/bin/sh
set -u

# Modem/WiFi readiness + guarded IPA bring-up (2026-07-03, v2).
#
# History: loading the IPA module while the modem userspace stack is broken
# or the modem is not up hard-resets the SoC ~30s later (TZ/XPU class, no
# panic). The pmOS SDM845/835 wikis document the required userspace set:
# rmtfs, pd-mapper, tqftpserv, qrtr(-ns). The modem chain itself
# (qcom_q6v5_mss, ath10k) loads early via modules-load.d like the proven
# June image; rmtfs -P needs the mss remoteproc device to exist, so the
# module must come first. Only IPA stays blacklisted from autoload, and is
# loaded here strictly AFTER the whole stack is verified healthy.

timeout="${RAZER_WIFI_READY_TIMEOUT:-75}"

wait_active() {
    svc="$1"; limit="$2"; t=0
    while [ "$t" -lt "$limit" ]; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo "razer-wifi-ready: $svc active after ${t}s"
            return 0
        fi
        sleep 1
        t=$((t + 1))
    done
    echo "razer-wifi-ready: $svc not active after ${limit}s" >&2
    return 1
}

modem_running() {
    for r in /sys/class/remoteproc/remoteproc*; do
        [ -f "$r/name" ] || continue
        if grep -q "4080000" "$r/name" 2>/dev/null; then
            [ "$(cat "$r/state" 2>/dev/null)" = "running" ] && return 0
        fi
    done
    return 1
}

wait_modem() {
    limit="$1"; t=0
    while [ "$t" -lt "$limit" ]; do
        if modem_running; then
            echo "razer-wifi-ready: modem running after ${t}s"
            return 0
        fi
        sleep 1
        t=$((t + 1))
    done
    echo "razer-wifi-ready: modem not running after ${limit}s" >&2
    return 1
}

STACK_OK=1
wait_active rmtfs.service 60      || STACK_OK=0
wait_active pd-mapper.service 30  || STACK_OK=0
wait_active tqftpserv.service 15  || STACK_OK=0
wait_active qrtr-ns.service 10    || STACK_OK=0
wait_modem 60                     || STACK_OK=0

# IPA (LTE data offload) is NOT loaded by default: on this rootfs, loading
# it hard-resets the SoC ~30s later even with a fully healthy modem stack
# (verified 2026-07-03; the June image was somehow immune — unresolved).
# WiFi does not need IPA. The production boot.img additionally carries
# module_blacklist=ipa as a kernel-level guard. To experiment with IPA,
# create /etc/razerphone2linux/enable-ipa AND remove the cmdline guard.
if [ "$STACK_OK" = "1" ] && [ -f /etc/razerphone2linux/enable-ipa ]; then
    modprobe ipa 2>/dev/null || true
    echo "razer-wifi-ready: modem stack healthy, ipa opt-in loaded"
elif [ "$STACK_OK" = "1" ]; then
    echo "razer-wifi-ready: modem stack healthy (ipa stays off by policy)"
else
    echo "razer-wifi-ready: modem stack NOT healthy" >&2
fi

elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
	if [ -d /sys/class/net/wlan0 ]; then
		nmcli radio wifi on 2>/dev/null || true
		echo "razer-wifi-ready: wlan0 available after ${elapsed}s"
		exit 0
	fi
	sleep 1
	elapsed=$((elapsed + 1))
done

echo "razer-wifi-ready: wlan0 not available after ${timeout}s; continuing without WiFi" >&2
exit 0
