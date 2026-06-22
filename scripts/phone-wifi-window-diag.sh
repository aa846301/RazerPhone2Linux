#!/bin/sh
set -eu

mode="${1:-status}"

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

print_status()
{
    echo "=== kernel ==="
    uname -a
    if [ -r /proc/config.gz ]; then
        zcat /proc/config.gz | egrep 'CONFIG_QCOM_Q6V5_MSS|CONFIG_RESET_QCOM_PDC|CONFIG_QCOM_PD_MAPPER|CONFIG_QCOM_SYSMON|CONFIG_ATH10K_SNOC|CONFIG_DYNAMIC_DEBUG' || true
    fi

    echo "=== modules ==="
    lsmod | egrep 'qcom_q6v5_mss|ath10k|qcom_pd_mapper|qcom_sysmon|qrtr|rmi_i2c' || true

    echo "=== autoload policy ==="
    cat /etc/modules-load.d/razer-aura.conf 2>/dev/null || true
    cat /etc/modprobe.d/razer-late-modem-test.conf 2>/dev/null || true

    echo "=== remoteproc ==="
    for r in /sys/class/remoteproc/remoteproc*; do
        [ -e "$r/name" ] || continue
        echo "$r"
        cat "$r/name" "$r/state" "$r/recovery" 2>/dev/null || true
    done

    echo "=== services ==="
    systemctl --no-pager --plain is-active rmtfs qrtr-ns tqftpserv NetworkManager helixscreen 2>/dev/null || true

    echo "=== links ==="
    ip -br link
    ls -la /sys/class/ieee80211 2>/dev/null || true

    echo "=== qrtr ==="
    qrtr-lookup 2>/dev/null || true
}

run_late_start()
{
    if ! lsmod | grep -q '^qcom_q6v5_mss '; then
        modprobe qcom_q6v5_mss
    fi
    sleep 1

    MSS="$(find_mss || true)"
    if [ -z "$MSS" ]; then
        echo "MSS_NOT_FOUND"
        exit 3
    fi

    echo disabled > "$MSS/recovery" 2>/dev/null || true
    systemctl reset-failed rmtfs.service 2>/dev/null || true
    systemctl restart rmtfs.service 2>/dev/null || true
    sleep 2

    state="$(cat "$MSS/state" 2>/dev/null || true)"
    echo "MSS state before=$state"
    if [ "$state" != "running" ]; then
        echo start > "$MSS/state" || true
    fi

    sleep 2
    echo "MSS state after start=$(cat "$MSS/state" 2>/dev/null || true)"

    echo "=== load ath10k ==="
    modprobe ath10k_core || true
    modprobe ath10k_snoc || true

    for i in 1 2 3 4 5 6 7 8; do
        echo "=== poll $i ==="
        cat "$MSS/name" "$MSS/state" "$MSS/recovery" 2>/dev/null || true
        ip -br link
        ls -la /sys/class/ieee80211 2>/dev/null || true
        qrtr-lookup 2>/dev/null | grep -E '(^ *69|WLFW|wlan|Service|  *66|  *43|  *14|  *64|4096)' || true
        sleep 5
    done
}

case "$mode" in
    status)
        print_status
        ;;
    late-start)
        print_status
        run_late_start
        ;;
    *)
        echo "usage: $0 [status|late-start]" >&2
        exit 2
        ;;
esac

echo "=== rmtfs tail ==="
journalctl -u rmtfs -b --no-pager | tail -140 || true

echo "=== tqftpserv tail ==="
journalctl -u tqftpserv -b --no-pager | tail -140 || true

echo "=== dmesg tail ==="
dmesg --time-format=iso |
    egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|rmtfs|glink|firmware|dog' |
    tail -260
