#!/bin/bash
# ==========================================================================
# Razer Phone 2 (aura) - Ubuntu Noble ARM64 Rootfs Builder
# ==========================================================================
# Creates an Ubuntu 24.04 (Noble) ARM64 root filesystem image configured
# for the Razer Phone 2 running mainline Linux with KlipperScreen.
#
# Usage: sudo bash 03-build-rootfs.sh
# Must be run as root (sudo) for debootstrap and chroot operations.
#
# Prerequisites:
#   - Run 01-setup-environment.sh first
#   - Run 02-build-kernel.sh first (modules needed)
# ==========================================================================

set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
OUTPUT_DIR="$WORKDIR/output"
ROOTFS_DIR="$WORKDIR/rootfs"
ROOTFS_IMG="$ROOTFS_DIR/rootfs-noble.img"
CHROOT_DIR="$ROOTFS_DIR/chroot"
FIRMWARE_DIR="$WORKDIR/firmware"
WIN_OUTPUT_DIR="/mnt/c/repo/razorphone2linux/output"
OUTPUT_ROOTFS_IMG="$OUTPUT_DIR/rootfs.img"

# Kernel version (detect from modules_install)
KERNEL_VERSION=$(ls "$OUTPUT_DIR/modules_install/lib/modules/" 2>/dev/null | head -1)
if [ -z "$KERNEL_VERSION" ]; then
    echo "ERROR: No kernel modules found in $OUTPUT_DIR/modules_install/"
    echo "Please run 02-build-kernel.sh first."
    exit 1
fi

HOSTNAME="razer-aura"
USERNAME="klipper"
# Default password - CHANGE THIS after first boot!
USER_PASSWORD="klipper"
ROOTFS_SIZE_GB=6
MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"

echo "========================================"
echo " Razer Phone 2 - Rootfs Builder"
echo "========================================"
echo "Distribution: Ubuntu Noble 24.04 ARM64"
echo "Kernel:       $KERNEL_VERSION"
echo "Image size:   ${ROOTFS_SIZE_GB}GB"
echo "Hostname:     $HOSTNAME"
echo "User:         $USERNAME"
echo ""

# Must be root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)."
    exit 1
fi

# -------------------------------------------------------
# Step 1: Create rootfs image
# -------------------------------------------------------
echo "[1/10] Creating ${ROOTFS_SIZE_GB}GB rootfs image..."
mkdir -p "$ROOTFS_DIR" "$CHROOT_DIR"

dd if=/dev/zero of="$ROOTFS_IMG" bs=1G count="$ROOTFS_SIZE_GB" status=progress
mkfs.ext4 -L rootfs "$ROOTFS_IMG"

mount "$ROOTFS_IMG" "$CHROOT_DIR"
echo "  Rootfs image mounted at $CHROOT_DIR"

# -------------------------------------------------------
# Step 2: Debootstrap base system
# -------------------------------------------------------
echo "[2/10] Running debootstrap (this takes several minutes)..."
debootstrap --arch arm64 noble "$CHROOT_DIR" "$MIRROR"
echo "  Base system installed."

# -------------------------------------------------------
# Step 3: Mount virtual filesystems for chroot
# -------------------------------------------------------
echo "[3/10] Mounting virtual filesystems..."
mount --bind /proc "$CHROOT_DIR/proc"
mount --bind /dev "$CHROOT_DIR/dev"
mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
mount --bind /sys "$CHROOT_DIR/sys"

# -------------------------------------------------------
# Step 4: Configure APT sources (Tsinghua mirror)
# -------------------------------------------------------
echo "[4/10] Configuring APT sources..."
cat > "$CHROOT_DIR/etc/apt/sources.list" << 'APT_EOF'
# Ubuntu Ports (ARM64) - Tsinghua Mirror
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-backports main restricted universe multiverse

# Security updates (official)
deb http://ports.ubuntu.com/ubuntu-ports/ noble-security main restricted universe multiverse
APT_EOF

# -------------------------------------------------------
# Step 5: Configure system inside chroot
# -------------------------------------------------------
echo "[5/10] Configuring system inside chroot..."

cat > "$CHROOT_DIR/tmp/setup.sh" << SETUP_EOF
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt update && apt upgrade -y

# Set locale
apt install -y locales
locale-gen en_US.UTF-8
locale-gen zh_TW.UTF-8
update-locale LANG=en_US.UTF-8

# Set timezone
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Taipei /etc/localtime
echo "Asia/Taipei" > /etc/timezone

# Set hostname
echo '$HOSTNAME' > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME

::1         localhost ip6-localhost ip6-loopback
HOSTS_EOF

# Create fstab
cat > /etc/fstab << FSTAB_EOF
# Razer Phone 2 - Mainline Linux fstab
# <file system>                          <mount point>  <type>  <options>           <dump>  <pass>
/dev/disk/by-partlabel/userdata          /              ext4    errors=remount-ro   0       1
tmpfs                                    /tmp           tmpfs   defaults,nosuid     0       0
FSTAB_EOF

# Remove netplan (use NetworkManager instead)
apt purge -y netplan.io 2>/dev/null || true

# Create user
useradd -m -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
usermod -aG sudo $USERNAME

# Set root password (same as user for convenience - change later!)
echo "root:$USER_PASSWORD" | chpasswd

# Install essential packages
# rmtfs: Qualcomm remote filesystem daemon - modem/WiFi firmware loader depends on this
# qrtr-tools: Qualcomm IPC Router - required by ath10k_snoc and modem subsystem
apt install -y \
    bash-completion \
    nano vim \
    chrony \
    locales \
    sudo \
    curl wget \
    network-manager \
    openssh-server \
    initramfs-tools \
    wpasupplicant \
    kmod \
    rmtfs \
    qrtr-tools \
    udev systemd-sysv \
    iproute2 iputils-ping \
    dbus \
    usbutils pciutils \
    evtest \
    htop \
    ca-certificates \
    gnupg

# Enable NetworkManager
systemctl enable NetworkManager

# Enable SSH
systemctl enable ssh

# -------------------------------------------------------
# Auto-resize filesystem on first boot
# -------------------------------------------------------
cat > /etc/systemd/system/resizefs.service << 'RESIZE_EOF'
[Unit]
Description=Expand root filesystem to fill partition
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'exec /usr/sbin/resize2fs \$(findmnt -nvo SOURCE /)'
ExecStartPost=/usr/bin/systemctl disable resizefs.service
RemainAfterExit=true

[Install]
WantedBy=default.target
RESIZE_EOF
systemctl enable resizefs.service

# -------------------------------------------------------
# Serial console on UART (debug)
# -------------------------------------------------------
cat > /etc/systemd/system/serial-getty@ttyMSM0.service << 'UART_EOF'
[Unit]
Description=Serial Console on ttyMSM0 (UART Debug)

[Service]
ExecStart=-/usr/sbin/agetty -L 115200 ttyMSM0 xterm-256color
Type=idle
Restart=always
RestartSec=0

[Install]
WantedBy=multi-user.target
UART_EOF
systemctl enable serial-getty@ttyMSM0.service

# -------------------------------------------------------
# Serial console on USB gadget
# -------------------------------------------------------
cat > /etc/systemd/system/serial-getty@ttyGS0.service << 'USB_EOF'
[Unit]
Description=Serial Console on ttyGS0 (USB Gadget)

[Service]
ExecStart=-/usr/sbin/agetty -L 115200 ttyGS0 xterm-256color
Type=idle
Restart=always
RestartSec=0

[Install]
WantedBy=multi-user.target
USB_EOF
systemctl enable serial-getty@ttyGS0.service

# -------------------------------------------------------
# USB ACM serial gadget (Windows-visible debug console)
# -------------------------------------------------------
cat > /usr/local/bin/usb-gadget-setup.sh << 'GADGET_EOF'
#!/bin/bash
set -euo pipefail

log() { echo "usb-gadget: $*" > /dev/kmsg 2>/dev/null || true; }

UDC=""
for _ in $(seq 1 30); do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -n 1 || true)
    [ -n "$UDC" ] && break
    sleep 0.2
done

if [ -z "$UDC" ]; then
    log "no UDC available"
    exit 0
fi

mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

GADGET=/sys/kernel/config/usb_gadget/g1
if [ -d "$GADGET" ]; then
    echo "" > "$GADGET/UDC" 2>/dev/null || true
    find "$GADGET/configs" -type l -delete 2>/dev/null || true
fi

mkdir -p "$GADGET/strings/0x409" "$GADGET/configs/c.1/strings/0x409"
echo 0x18d1 > "$GADGET/idVendor"
echo 0x4ee7 > "$GADGET/idProduct"
echo 0x0200 > "$GADGET/bcdUSB"
echo 0x0100 > "$GADGET/bcdDevice"
echo 0x02 > "$GADGET/bDeviceClass"
echo 0x02 > "$GADGET/bDeviceSubClass"
echo 0x01 > "$GADGET/bDeviceProtocol"
echo "Razer" > "$GADGET/strings/0x409/manufacturer"
echo "Razer Phone 2 Linux Console" > "$GADGET/strings/0x409/product"
echo "aura-linux" > "$GADGET/strings/0x409/serialnumber"
echo "ACM serial console" > "$GADGET/configs/c.1/strings/0x409/configuration"
echo 120 > "$GADGET/configs/c.1/MaxPower"

mkdir -p "$GADGET/functions/acm.usb0"
ln -sf "$GADGET/functions/acm.usb0" "$GADGET/configs/c.1/acm.usb0"
echo "$UDC" > "$GADGET/UDC"
log "bound ACM serial gadget to $UDC"
GADGET_EOF
chmod +x /usr/local/bin/usb-gadget-setup.sh

cat > /etc/systemd/system/usb-gadget.service << 'GADGET_SERVICE_EOF'
[Unit]
Description=USB ACM serial gadget
After=local-fs.target
Before=serial-getty@ttyGS0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usb-gadget-setup.sh

[Install]
WantedBy=multi-user.target
GADGET_SERVICE_EOF
systemctl enable usb-gadget.service

mkdir -p /etc/systemd/system/serial-getty@ttyGS0.service.d
cat > /etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf << 'GADGET_DROPIN_EOF'
[Unit]
After=usb-gadget.service
Requires=usb-gadget.service
GADGET_DROPIN_EOF

# -------------------------------------------------------
# Kernel modules load configuration
# -------------------------------------------------------
cat > /etc/modules-load.d/razer-aura.conf << 'MODULES_EOF'
# Razer Phone 2 kernel modules
# Full display stack. simpledrm keeps the splash/framebuffer alive before
# these probe, which makes panel bring-up failures recoverable over serial/SSH.
msm
panel-novatek-nt36830
# WiFi
ath10k_snoc
# Touchscreen
rmi_i2c
MODULES_EOF

# -------------------------------------------------------
# Disable unnecessary services for faster boot
# -------------------------------------------------------
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable fstrim.timer 2>/dev/null || true

# Clean up
apt clean
rm -f /tmp/*
history -c

echo "System configuration complete."
SETUP_EOF

chmod +x "$CHROOT_DIR/tmp/setup.sh"
chroot "$CHROOT_DIR" /tmp/setup.sh

# -------------------------------------------------------
# Step 6: Install kernel modules
# -------------------------------------------------------
echo "[6/10] Installing kernel modules (version $KERNEL_VERSION)..."
rsync -av --progress \
    "$OUTPUT_DIR/modules_install/lib/modules/$KERNEL_VERSION" \
    "$CHROOT_DIR/lib/modules/"

# Run depmod inside chroot
chroot "$CHROOT_DIR" depmod -a "$KERNEL_VERSION"

echo "  Kernel modules installed."

# -------------------------------------------------------
# Step 6b: Generate initramfs after kernel modules exist
# -------------------------------------------------------
echo "[6b/10] Generating Ubuntu initramfs..."

chroot "$CHROOT_DIR" update-initramfs -c -k "$KERNEL_VERSION"

INITRD_SRC="$CHROOT_DIR/boot/initrd.img-$KERNEL_VERSION"
if [ ! -f "$INITRD_SRC" ]; then
    echo "ERROR: initramfs was not generated at /boot/initrd.img-$KERNEL_VERSION"
    exit 1
fi

cp -f "$INITRD_SRC" "$OUTPUT_DIR/initrd.img-$KERNEL_VERSION"
cp -f "$INITRD_SRC" "$OUTPUT_DIR/initrd.img"
echo "  Initramfs copied to $OUTPUT_DIR/initrd.img-$KERNEL_VERSION"

# -------------------------------------------------------
# Step 7: Install firmware blobs
# -------------------------------------------------------
echo "[7/10] Installing firmware blobs..."

# 7a: Proprietary blobs (adsp, cdsp, gpu zap, venus) from stock ROM.
if [ -d "$FIRMWARE_DIR" ] && [ "$(ls -A "$FIRMWARE_DIR" 2>/dev/null)" ]; then
    mkdir -p "$CHROOT_DIR/usr/lib/firmware"
    cp -rv "$FIRMWARE_DIR"/* "$CHROOT_DIR/usr/lib/firmware/"
    echo "  Proprietary firmware installed."
else
    echo "  NOTE: $FIRMWARE_DIR is empty."
    echo "  WiFi (ath10k), GPU (a630_zap), ADSP, CDSP will not work until"
    echo "  you run wsl-scripts/extract-qcom-firmware.sh and rebuild rootfs."
fi

# 7b: WCN3990 WiFi firmware from linux-firmware (open-source, no ROM needed).
echo "  Downloading WCN3990 (ath10k) firmware from linux-firmware git..."
LINUX_FW_BASE="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"
ATH10K_DIR="$CHROOT_DIR/usr/lib/firmware/ath10k/WCN3990/hw1.0"
mkdir -p "$ATH10K_DIR"

for fw_file in firmware-5.bin board.bin board-2.bin; do
    if wget -q --timeout=30 -O "$ATH10K_DIR/$fw_file" \
            "${LINUX_FW_BASE}/ath10k/WCN3990/hw1.0/${fw_file}"; then
        echo "  Downloaded $fw_file ($(du -h "$ATH10K_DIR/$fw_file" | cut -f1))"
    else
        echo "  WARNING: Failed to download $fw_file - WiFi may not work"
        rm -f "$ATH10K_DIR/$fw_file"
    fi
done

# 7c: Adreno 630 firmware (a630_gmu.bin) from linux-firmware.
#     The GPU zap shader (a630_zap.mbn) still needs the stock ROM.
ADRENO_DIR="$CHROOT_DIR/usr/lib/firmware/qcom"
mkdir -p "$ADRENO_DIR"
if wget -q --timeout=30 -O "$ADRENO_DIR/a630_gmu.bin" \
        "${LINUX_FW_BASE}/qcom/a630_gmu.bin"; then
    echo "  Downloaded a630_gmu.bin ($(du -h "$ADRENO_DIR/a630_gmu.bin" | cut -f1))"
else
    echo "  WARNING: Failed to download a630_gmu.bin"
    rm -f "$ADRENO_DIR/a630_gmu.bin"
fi

# -------------------------------------------------------
# Step 8: Install KlipperScreen dependencies
# -------------------------------------------------------
echo "[8/10] Installing KlipperScreen dependencies..."
cat > "$CHROOT_DIR/tmp/install-klipperscreen-deps.sh" << 'KS_EOF'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# X11 display server (minimal, for KlipperScreen)
apt install -y \
    xserver-xorg-core \
    xinit \
    xinput \
    x11-xserver-utils \
    xserver-xorg-input-evdev \
    xserver-xorg-input-libinput \
    xserver-xorg-video-fbdev \
    xserver-xorg-legacy

# Python and GTK dependencies for KlipperScreen
apt install -y \
    python3-venv \
    python3-dev \
    python3-gi \
    python3-gi-cairo \
    python3-cairo \
    gir1.2-gtk-3.0 \
    libgirepository1.0-dev \
    gcc \
    libcairo2-dev \
    pkg-config \
    librsvg2-common \
    libopenjp2-7 \
    libdbus-glib-1-dev \
    autoconf

# Additional useful packages
apt install -y \
    git \
    python3-pip

apt clean
KS_EOF

chmod +x "$CHROOT_DIR/tmp/install-klipperscreen-deps.sh"
chroot "$CHROOT_DIR" /tmp/install-klipperscreen-deps.sh

echo "  KlipperScreen dependencies installed."

# -------------------------------------------------------
# Step 9: Install and configure KlipperScreen
# -------------------------------------------------------
echo "[9/10] Installing KlipperScreen..."
cat > "$CHROOT_DIR/tmp/install-klipperscreen.sh" << 'KSINSTALL_EOF'
#!/bin/bash
set -euo pipefail

KS_USER="klipper"
KS_HOME="/home/$KS_USER"

# Clone KlipperScreen
cd "$KS_HOME"
if [ ! -d "KlipperScreen" ]; then
    su -c "git clone https://github.com/KlipperScreen/KlipperScreen.git" "$KS_USER"
fi

# Create Python virtual environment and install dependencies
su -c "python3 -m venv $KS_HOME/.KlipperScreen-env" "$KS_USER"
su -c "$KS_HOME/.KlipperScreen-env/bin/pip install --upgrade pip" "$KS_USER"
su -c "$KS_HOME/.KlipperScreen-env/bin/pip install -r $KS_HOME/KlipperScreen/scripts/KlipperScreen-requirements.txt" "$KS_USER"

# -------------------------------------------------------
# Create X11 auto-start service
# -------------------------------------------------------
cat > /etc/systemd/system/xinit-klipperscreen.service << 'XINIT_EOF'
[Unit]
Description=X11 Display Server for KlipperScreen
After=systemd-user-sessions.service
Wants=network-online.target

[Service]
Type=simple
User=klipper
Environment="DISPLAY=:0"
# Start X11 with minimal configuration, no screen blanking
ExecStart=/usr/bin/xinit /home/klipper/.KlipperScreen-env/bin/python /home/klipper/KlipperScreen/screen.py -- :0 vt1 -keeptty -noreset -dpms
Restart=on-failure
RestartSec=5s
# Allow X to access display hardware
SupplementaryGroups=video input render tty

[Install]
WantedBy=multi-user.target
XINIT_EOF

# Enable auto-start
systemctl enable xinit-klipperscreen.service

# -------------------------------------------------------
# Configure X11
# -------------------------------------------------------
# Allow non-root X server
cat > /etc/X11/Xwrapper.config << 'XWRAP_EOF'
allowed_users=anybody
needs_root_rights=yes
XWRAP_EOF

# Disable screen blanking and DPMS in X11
mkdir -p "$KS_HOME/.xinitrc.d"
cat > "$KS_HOME/.xinitrc" << 'XINITRC_EOF'
#!/bin/sh
# Disable screen blanking and DPMS
xset s off
xset -dpms
xset s noblank

# Disable touchscreen right-click emulation
# (adjust event device as needed after first boot)
# xinput set-prop "Synaptics RMI4" "libinput Click Method Enabled" 1 0

# Start KlipperScreen
exec /home/klipper/.KlipperScreen-env/bin/python /home/klipper/KlipperScreen/screen.py
XINITRC_EOF
chown "$KS_USER:$KS_USER" "$KS_HOME/.xinitrc"
chmod +x "$KS_HOME/.xinitrc"

# -------------------------------------------------------
# Create default KlipperScreen config
# -------------------------------------------------------
mkdir -p "$KS_HOME/printer_data/config"
cat > "$KS_HOME/printer_data/config/KlipperScreen.conf" << 'KSCONF_EOF'
# KlipperScreen Configuration for Razer Phone 2
# Adjust moonraker_host/port to match your Klipper setup

[main]
# Time format: 24h
24htime: True

# Screen blanking timeout (0 = disabled)
screen_blanking: off

# Moonraker connection (adjust IP to your Klipper host)
moonraker_host: 127.0.0.1
moonraker_port: 7125

[printer Printer]
moonraker_host: 127.0.0.1
moonraker_port: 7125
KSCONF_EOF
chown -R "$KS_USER:$KS_USER" "$KS_HOME/printer_data"

echo "KlipperScreen installation complete."
KSINSTALL_EOF

chmod +x "$CHROOT_DIR/tmp/install-klipperscreen.sh"
chroot "$CHROOT_DIR" /tmp/install-klipperscreen.sh

echo "  KlipperScreen installed and configured for auto-start."

# -------------------------------------------------------
# Step 10: Cleanup and unmount
# -------------------------------------------------------
echo "[10/10] Cleaning up and creating sparse image..."

# Final cleanup inside chroot
chroot "$CHROOT_DIR" bash -c "apt clean && rm -rf /tmp/* && rm -f /var/cache/apt/archives/*.deb"

# Unmount virtual filesystems
umount "$CHROOT_DIR/proc" 2>/dev/null || true
umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
umount "$CHROOT_DIR/dev" 2>/dev/null || true
umount "$CHROOT_DIR/sys" 2>/dev/null || true

# Unmount rootfs
umount "$CHROOT_DIR"

# Create Android sparse image for fastboot
SPARSE_IMG="$OUTPUT_DIR/rootfs-sparse.img"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
cp -f "$ROOTFS_IMG" "$OUTPUT_ROOTFS_IMG"

mkdir -p "$WIN_OUTPUT_DIR"
cp -f "$OUTPUT_ROOTFS_IMG" "$WIN_OUTPUT_DIR/rootfs.img"
cp -f "$SPARSE_IMG" "$WIN_OUTPUT_DIR/rootfs-sparse.img"

echo ""
echo "========================================"
echo " Rootfs build complete!"
echo "========================================"
echo ""
echo "Outputs:"
echo "  Raw image:    $OUTPUT_ROOTFS_IMG"
echo "  Sparse image: $SPARSE_IMG"
echo ""
echo "Configuration:"
echo "  User:     $USERNAME / $USER_PASSWORD"
echo "  Root:     root / $USER_PASSWORD"
echo "  Hostname: $HOSTNAME"
echo "  SSH:      enabled"
echo "  WiFi:     use 'nmtui' or 'nmcli' after boot"
echo ""
echo "  KlipperScreen: auto-starts on boot via xinit"
echo "  Serial debug:  ttyMSM0 (UART) and ttyGS0 (USB gadget)"
echo ""
echo "IMPORTANT: Change passwords after first boot!"
echo ""
echo "Next: Run bash 04-make-boot-image.sh"
