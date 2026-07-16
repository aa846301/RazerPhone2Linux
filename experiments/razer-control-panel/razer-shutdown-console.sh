#!/bin/sh

# ExecStop also runs for an ordinary panel restart. Only take over the display
# while PID 1 is actually shutting the system down.
[ "$(systemctl is-system-running 2>/dev/null || true)" = "stopping" ] || exit 0

# Re-enable systemd status and kernel INFO messages only for shutdown. The
# normal boot remains quiet.
kill -RTMIN+20 1 2>/dev/null || true
dmesg -n 6 2>/dev/null || true

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
    journalctl -b -u systemd-logind -n 6 -o short-monotonic --no-pager 2>/dev/null || true
    printf '\nStopping services and powering off hardware...\n'
} > /dev/tty1 2>/dev/null || true
