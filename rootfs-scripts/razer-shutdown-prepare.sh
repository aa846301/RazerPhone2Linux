#!/bin/bash
set -u

# This service also receives ExecStop during manual restarts. Only alter the
# display and hardware policy while PID 1 is actually shutting down.
[ "$(systemctl is-system-running 2>/dev/null || true)" = "stopping" ] || exit 0

# Bring back the real kernel/systemd console after the normal quiet boot.
kill -RTMIN+20 1 2>/dev/null || true
dmesg --console-level info 2>/dev/null || true
chvt 1 2>/dev/null || true
for console in /sys/class/vtconsole/vtcon*; do
    [ -r "$console/name" ] || continue
    case "$(cat "$console/name" 2>/dev/null)" in
        *"frame buffer"*) printf '1' > "$console/bind" 2>/dev/null || true ;;
    esac
done
printf '0' > /sys/class/graphics/fb0/blank 2>/dev/null || true

{
    printf '\033[2J\033[H'
    printf 'Razer Phone 2 shutting down\n\n'
} > /dev/tty1 2>/dev/null || true

# An intermittent powered-off hang showed UFS devfreq commands racing the
# final UFS shutdown. Freeze clock scaling while userspace and storage are
# still fully available; this does not affect normal runtime performance.
ufs_clkscale=/sys/bus/platform/devices/1d84000.ufshc/clkscale_enable
[ -w "$ufs_clkscale" ] && printf '0' > "$ufs_clkscale" 2>/dev/null || true

# Let ath10k finish its disconnect while MSS/WMI is still alive. The modem
# stop service runs immediately after this service during shutdown.
ip link set wlan0 down 2>/dev/null || true
sleep 1
