#!/bin/sh
set -eu

print_prop()
{
    path="$1"
    label="$2"
    if [ ! -e "$path" ]; then
        echo "$label: MISSING"
        return
    fi

    echo "=== $label ==="
    if file "$path" 2>/dev/null | grep -q text; then
        tr '\0' '\n' < "$path" 2>/dev/null || true
    else
        echo "-- strings --"
        tr '\0' '\n' < "$path" 2>/dev/null | sed -n '1,40p' || true
        echo "-- u32 --"
        od -An -tx4 -v "$path" 2>/dev/null | sed -n '1,20p' || true
    fi
}

echo "=== baseline ==="
uname -a
ip -br link
systemctl --no-pager --plain is-active rmtfs qrtr-ns tqftpserv NetworkManager helixscreen 2>/dev/null || true
lsmod | egrep 'qcom_q6v5_mss|ath10k|qcom_pd_mapper|qcom_sysmon|qrtr|pdr|rmi_i2c' || true
qrtr-lookup 2>/dev/null || true

echo "=== remoteproc ==="
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    echo "$r"
    cat "$r/name" "$r/state" "$r/recovery" 2>/dev/null || true
done

echo "=== root compatible ==="
print_prop /proc/device-tree/compatible compatible

MSS_DT=""
for p in /proc/device-tree/soc@0/remoteproc@4080000 /proc/device-tree/soc@0/remoteproc-4080000 /proc/device-tree/soc@0/*4080000*; do
    [ -d "$p" ] || continue
    if [ -e "$p/compatible" ]; then
        MSS_DT="$p"
        break
    fi
done

echo "=== MSS DT path ==="
echo "${MSS_DT:-MISSING}"
if [ -n "$MSS_DT" ]; then
    for prop in compatible status reg-names reset-names firmware-name memory-region-names interrupt-names qcom,smem-state-names; do
        print_prop "$MSS_DT/$prop" "mss/$prop"
    done
    for prop in reg resets interrupts qcom,halt-regs qcom,smem-states qcom,qmp qcom,proxy-clock-names qcom,active-clock-names; do
        print_prop "$MSS_DT/$prop" "mss/$prop"
    done
fi

WIFI_DT=""
for p in /proc/device-tree/soc@0/wifi@18800000 /proc/device-tree/soc@0/*18800000*; do
    [ -d "$p" ] || continue
    if [ -e "$p/compatible" ]; then
        WIFI_DT="$p"
        break
    fi
done

echo "=== WiFi DT path ==="
echo "${WIFI_DT:-MISSING}"
if [ -n "$WIFI_DT" ]; then
    for prop in compatible status qcom,calibration-variant qcom,ath10k-calibration-variant memory-region-names; do
        print_prop "$WIFI_DT/$prop" "wifi/$prop"
    done
    for prop in reg interrupts iommus memory-region; do
        print_prop "$WIFI_DT/$prop" "wifi/$prop"
    done
fi

echo "=== modem service registry files ==="
find /lib/firmware /usr/lib/firmware -type f \( -name '*modem*.jsn' -o -name '*wlan*.jsn' -o -name '*servreg*.jsn' -o -name '*.jsn' \) 2>/dev/null | sort | sed -n '1,120p'

echo "=== modem/wlan jsn snippets ==="
for f in $(find /lib/firmware /usr/lib/firmware -type f \( -name '*modem*.jsn' -o -name '*wlan*.jsn' -o -name '*.jsn' \) 2>/dev/null | sort | sed -n '1,40p'); do
    echo "--- $f ---"
    grep -aE 'msm/modem|wlan_pd|root_pd|tms/servreg|wlan|servreg|instance|service' "$f" 2>/dev/null | sed -n '1,80p' || true
done

echo "=== module info ==="
for m in qcom_q6v5_mss qcom_pd_mapper qcom_sysmon ath10k_snoc ath10k_core; do
    echo "--- $m ---"
    modinfo "$m" 2>/dev/null | egrep 'filename|depends|alias|parm|version|description' || true
done

echo "=== trace/debug availability ==="
for d in /sys/kernel/tracing/events /sys/kernel/debug/tracing/events; do
    [ -d "$d" ] || continue
    echo "--- $d ---"
    find "$d" -maxdepth 2 -type d 2>/dev/null | grep -Ei 'qmi|qrtr|remoteproc|rproc|rpmsg|glink|pdr|qcom' | sort | sed -n '1,120p'
done

echo "=== recent dmesg ==="
dmesg --time-format=iso |
    egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|rmtfs|glink|sysmon|pdr|dog' |
    tail -220
