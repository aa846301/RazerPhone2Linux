#!/bin/sh
# HA dashboard kiosk: sway (landscape + 2x scale via config) + epiphany at
# the official Home Assistant demo, hardware GL on Adreno 630 (freedreno).
exec > /tmp/kiosk.log 2>&1

systemctl start seatd 2>/dev/null || true

: "${XDG_RUNTIME_DIR:=/run/razer-kiosk}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

export WLR_NO_HARDWARE_CURSORS=1

exec dbus-run-session -- sway -c /opt/razer-ha-kiosk/sway-kiosk.conf
