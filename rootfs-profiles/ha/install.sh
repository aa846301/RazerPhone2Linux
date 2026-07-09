#!/bin/bash
set -euo pipefail

: "${CHROOT_DIR:?}"
: "${PROJECT_DIR:?}"

cp -a "$PROJECT_DIR/rootfs-scripts/kiosk-prototype" "$CHROOT_DIR/opt/razer-ha-kiosk"
chmod 0755 "$CHROOT_DIR/opt/razer-ha-kiosk/hakiosk.sh"

chroot "$CHROOT_DIR" /bin/bash -s <<'CHROOT_EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y \
    cage \
    epiphany-browser \
    seatd \
    sway \
    wlr-randr \
    libinput-tools \
    wev \
    evtest

for group in video input render seat; do
    getent group "$group" >/dev/null || groupadd -r "$group"
done
useradd -r -s /usr/sbin/nologin -G video,input,render,seat razer-kiosk 2>/dev/null || true
install -d -o razer-kiosk -g razer-kiosk /var/lib/razer-kiosk

cat > /etc/systemd/system/razer-ha-kiosk.service <<'SERVICE_EOF'
[Unit]
Description=Razer Phone 2 Home Assistant kiosk prototype
After=network-online.target razer-wifi-ready.service
Wants=network-online.target razer-wifi-ready.service

[Service]
User=razer-kiosk
Environment=XDG_RUNTIME_DIR=/run/razer-kiosk
Environment=MOZ_ENABLE_WAYLAND=1
ExecStartPre=/usr/bin/install -d -o razer-kiosk -g razer-kiosk /run/razer-kiosk
ExecStart=/opt/razer-ha-kiosk/hakiosk.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl enable seatd.service
systemctl enable razer-ha-kiosk.service
CHROOT_EOF
