#!/bin/bash
# Final target userspace for Razer Phone 2:
# Klipper + Moonraker backend and HelixScreen fbdev touchscreen UI.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
source /tmp/userspace.env

KLIPPER_USER="${KLIPPER_USER:-klipper}"
KLIPPER_HOME="/home/$KLIPPER_USER"
DATA_DIR="$KLIPPER_HOME/printer_data"
CONFIG_DIR="$DATA_DIR/config"
LOG_DIR="$DATA_DIR/logs"
COMMS_DIR="$DATA_DIR/comms"

apt-get update
apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    python3 \
    python3-dev \
    python3-venv \
    python3-pip \
    build-essential \
    pkg-config \
    libffi-dev \
    libssl-dev \
    libjpeg-dev \
    zlib1g-dev \
    libopenjp2-7 \
    can-utils \
    avrdude \
    gcc-avr \
    binutils-avr \
    avr-libc \
    stm32flash \
    libnewlib-arm-none-eabi \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi \
    jq

apt-get install -y --no-install-recommends libturbojpeg || \
    apt-get install -y --no-install-recommends libturbojpeg0 || true
apt-get install -y --no-install-recommends libasound2t64 || \
    apt-get install -y --no-install-recommends libasound2

install -d -m 0755 "$CONFIG_DIR" "$LOG_DIR" "$COMMS_DIR" "$DATA_DIR/gcodes" "$DATA_DIR/systemd"
chown -R "$KLIPPER_USER:$KLIPPER_USER" "$DATA_DIR"
for group in video input render tty; do
    getent group "$group" >/dev/null || groupadd -r "$group"
done
usermod -aG video,input,render,tty "$KLIPPER_USER"

install_repo() {
    local url="$1"
    local commit="$2"
    local dest="$3"
    if [ ! -d "$dest/.git" ]; then
        su -s /bin/bash -c "git clone --filter=blob:none --no-checkout '$url' '$dest'" "$KLIPPER_USER"
    fi
    su -s /bin/bash -c "git -C '$dest' fetch --depth=1 origin '$commit'" "$KLIPPER_USER"
    su -s /bin/bash -c "git -C '$dest' checkout --detach '$commit'" "$KLIPPER_USER"
}

install_repo "$KLIPPER_REPO" "$KLIPPER_COMMIT" "$KLIPPER_HOME/klipper"
install_repo "$MOONRAKER_REPO" "$MOONRAKER_COMMIT" "$KLIPPER_HOME/moonraker"

if [ ! -x "$KLIPPER_HOME/klippy-env/bin/python" ]; then
    su -s /bin/bash -c "python3 -m venv '$KLIPPER_HOME/klippy-env'" "$KLIPPER_USER"
fi
su -s /bin/bash -c "'$KLIPPER_HOME/klippy-env/bin/pip' install --upgrade pip wheel" "$KLIPPER_USER"
su -s /bin/bash -c "'$KLIPPER_HOME/klippy-env/bin/pip' install -r '$KLIPPER_HOME/klipper/scripts/klippy-requirements.txt'" "$KLIPPER_USER"

if [ ! -x "$KLIPPER_HOME/moonraker-env/bin/python" ]; then
    su -s /bin/bash -c "python3 -m venv '$KLIPPER_HOME/moonraker-env'" "$KLIPPER_USER"
fi
su -s /bin/bash -c "'$KLIPPER_HOME/moonraker-env/bin/pip' install --upgrade pip wheel" "$KLIPPER_USER"
su -s /bin/bash -c "'$KLIPPER_HOME/moonraker-env/bin/pip' install -r '$KLIPPER_HOME/moonraker/scripts/moonraker-requirements.txt'" "$KLIPPER_USER"

if [ ! -f "$CONFIG_DIR/printer.cfg" ]; then
    cat > "$CONFIG_DIR/printer.cfg" <<'PRINTER_CFG_EOF'
[printer]
kinematics: none
max_velocity: 1
max_accel: 1

[virtual_sdcard]
path: ~/printer_data/gcodes

[display_status]

[pause_resume]
PRINTER_CFG_EOF
    chown "$KLIPPER_USER:$KLIPPER_USER" "$CONFIG_DIR/printer.cfg"
fi

cat > "$CONFIG_DIR/moonraker.conf" <<MOONRAKER_CFG_EOF
[server]
host: 0.0.0.0
port: 7125
klippy_uds_address: $COMMS_DIR/klippy.sock

[file_manager]
enable_object_processing: False

[authorization]
trusted_clients:
    127.0.0.1
    192.168.0.0/16
    10.0.0.0/8
    172.16.0.0/12

[machine]
provider: systemd_dbus
MOONRAKER_CFG_EOF
chown "$KLIPPER_USER:$KLIPPER_USER" "$CONFIG_DIR/moonraker.conf"

cat > /etc/systemd/system/klipper.service <<KLIPPER_SERVICE_EOF
[Unit]
Description=Klipper 3D Printer Firmware
After=network.target

[Service]
Type=simple
User=$KLIPPER_USER
WorkingDirectory=$KLIPPER_HOME/klipper
ExecStart=$KLIPPER_HOME/klippy-env/bin/python $KLIPPER_HOME/klipper/klippy/klippy.py $CONFIG_DIR/printer.cfg -l $LOG_DIR/klippy.log -a $COMMS_DIR/klippy.sock
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
KLIPPER_SERVICE_EOF

cat > "$DATA_DIR/systemd/moonraker.env" <<MOONRAKER_ENV_EOF
MOONRAKER_ARGS="$KLIPPER_HOME/moonraker/moonraker/moonraker.py -d $DATA_DIR -c $CONFIG_DIR/moonraker.conf"
MOONRAKER_ENV_EOF
chown "$KLIPPER_USER:$KLIPPER_USER" "$DATA_DIR/systemd/moonraker.env"

cat > /etc/systemd/system/moonraker.service <<MOONRAKER_SERVICE_EOF
[Unit]
Description=API Server for Klipper SV1
Requires=network-online.target
After=network-online.target klipper.service

[Service]
Type=simple
User=$KLIPPER_USER
SupplementaryGroups=sudo
WorkingDirectory=$KLIPPER_HOME/moonraker
EnvironmentFile=$DATA_DIR/systemd/moonraker.env
ExecStart=$KLIPPER_HOME/moonraker-env/bin/python \$MOONRAKER_ARGS
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
MOONRAKER_SERVICE_EOF

systemctl enable klipper.service
systemctl enable moonraker.service

# Pin HelixScreen to a tested release instead of installing whatever happens
# to be latest when a clean rootfs is built.
curl -fsSL "$HELIX_INSTALLER_URL" | sh -s -- --version "$HELIX_VERSION"

HELIX_DIR="$KLIPPER_HOME/helixscreen"
# The installer sees a QEMU chroot without a running systemd PID 1 and may use
# its SysV fallback, which starts Helix immediately. Stop it before returning;
# the real device will start the generated systemd unit on first boot.
if [ -x /etc/init.d/S90helixscreen ]; then
    /etc/init.d/S90helixscreen stop 2>/dev/null || true
fi
pkill -x helix-watchdog 2>/dev/null || true
pkill -x helix-screen 2>/dev/null || true
pkill -x helix-splash 2>/dev/null || true

if [ -f "$HELIX_DIR/config/helixscreen.service" ]; then
    sed \
        -e "s|@@HELIX_USER@@|$KLIPPER_USER|g" \
        -e "s|@@HELIX_GROUP@@|$KLIPPER_USER|g" \
        -e "s|@@INSTALL_DIR@@|$HELIX_DIR|g" \
        -e "s|@@INSTALL_PARENT@@|$KLIPPER_HOME|g" \
        "$HELIX_DIR/config/helixscreen.service" > /etc/systemd/system/helixscreen.service
fi

if [ -f /etc/systemd/system/helixscreen.service ]; then
    mkdir -p /etc/systemd/system/helixscreen.service.d
    cat > /etc/systemd/system/helixscreen.service.d/razer-fbdev.conf <<'HELIX_OVERRIDE_EOF'
[Service]
Environment="HELIX_DISPLAY_BACKEND=fbdev"
Environment="HELIX_DISPLAY_ROTATION=90"
Environment="HELIX_COLOR_SWAP_RB=1"
Environment="HELIX_TOUCH_DEVICE=/dev/input/event0"
Environment="HELIX_MOUSE_DEVICE="
HELIX_OVERRIDE_EOF
    systemctl enable helixscreen.service
fi

for cfg in \
    "$KLIPPER_HOME/helixscreen/config/settings.json" \
    "$CONFIG_DIR/helixscreen/settings.json" \
    /opt/helixscreen/config/settings.json \
    /root/helixscreen/config/settings.json; do
    [ -f "$cfg" ] || continue
    python3 - "$cfg" <<'PYEOF'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["active_printer_id"] = data.get("active_printer_id", "default")
data["wizard_completed"] = True
data.setdefault("display", {})
data["display"]["drm_device"] = ""
data["display"]["rotate"] = 90
data["display"]["rotation_probed"] = True
printers = data.setdefault("printers", {})
printer = printers.setdefault("default", {})
printer["moonraker_host"] = "127.0.0.1"
printer["moonraker_port"] = 7125
printer["moonraker_api_key"] = False
path.write_text(json.dumps(data, indent=2) + "\n")
PYEOF
    chown "$KLIPPER_USER:$KLIPPER_USER" "$cfg" 2>/dev/null || true
done

systemctl daemon-reload
apt-get clean
