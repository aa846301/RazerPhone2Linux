#!/bin/bash
# ==========================================================================
# Razer Phone 2 - Rootfs Builder (resource-limited)
# Uses ionice + nice to reduce I/O impact on host system
# ==========================================================================
set -euo pipefail

WORKDIR=/home/dinochang/razorphone2linux
OUTPUT=$WORKDIR/output
ROOTFS_DIR=$WORKDIR/rootfs
ROOTFS_IMG=$ROOTFS_DIR/rootfs-noble.img
CHROOT_DIR=$ROOTFS_DIR/chroot
FIRMWARE_DIR=$WORKDIR/firmware

KVER=$(ls $OUTPUT/modules_install/lib/modules/ | head -1)
HOSTNAME="razer-aura"
USERNAME="klipper"
USER_PASSWORD="klipper"
ROOTFS_SIZE_GB=2
MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"

echo "========================================"
echo " Razer Phone 2 - Rootfs Builder"
echo "========================================"
echo "Kernel: $KVER"
echo "Size:   ${ROOTFS_SIZE_GB}GB"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run with sudo"; exit 1
fi

# Cleanup from previous runs
cleanup() {
    echo "Cleaning up mounts..."
    umount $CHROOT_DIR/proc 2>/dev/null || true
    umount $CHROOT_DIR/dev/pts 2>/dev/null || true
    umount $CHROOT_DIR/dev 2>/dev/null || true
    umount $CHROOT_DIR/sys 2>/dev/null || true
    umount $CHROOT_DIR 2>/dev/null || true
    losetup -D 2>/dev/null || true
}
trap cleanup EXIT

cleanup

# Step 1: Create image
echo "[1/8] Creating ${ROOTFS_SIZE_GB}GB image..."
mkdir -p $ROOTFS_DIR $CHROOT_DIR
rm -f $ROOTFS_IMG
dd if=/dev/zero of=$ROOTFS_IMG bs=1M count=$((ROOTFS_SIZE_GB * 1024)) status=progress
# -J size=32: reduce journal from default ~128MB to 32MB (saves sparse image size)
mkfs.ext4 -L rootfs -J size=32 -q $ROOTFS_IMG
mount $ROOTFS_IMG $CHROOT_DIR

# Step 2: Debootstrap (use ionice to limit I/O)
echo "[2/8] Debootstrap noble arm64 (this takes ~5 min)..."
ionice -c 3 nice -n 10 debootstrap --arch arm64 --variant=minbase \
    --include=systemd,systemd-sysv,udev,dbus,kmod,sudo,bash \
    noble $CHROOT_DIR $MIRROR

# Step 3: Mount for chroot
echo "[3/8] Mounting virtual filesystems..."
mount --bind /proc $CHROOT_DIR/proc
mount --bind /dev $CHROOT_DIR/dev
mount --bind /dev/pts $CHROOT_DIR/dev/pts
mount --bind /sys $CHROOT_DIR/sys

# Step 4: APT sources
echo "[4/8] Configuring APT..."
cat > $CHROOT_DIR/etc/apt/sources.list << 'APTEOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ noble-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ noble-security main restricted universe multiverse
APTEOF

# Step 5: System configuration
echo "[5/8] Configuring system..."
cat > $CHROOT_DIR/tmp/setup-system.sh << SYSEOF
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y locales network-manager openssh-server \
    wpasupplicant iproute2 iputils-ping nano curl wget \
    ca-certificates usbutils evtest htop chrony \
    initramfs-tools bash-completion gnupg

# Locale
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Timezone
ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime
echo "Asia/Taipei" > /etc/timezone

# Hostname
echo '$HOSTNAME' > /etc/hostname
cat > /etc/hosts << 'HOSTSEOF'
127.0.0.1 localhost
127.0.1.1 razer-aura
::1 localhost ip6-localhost ip6-loopback
HOSTSEOF

# fstab
cat > /etc/fstab << 'FSTABEOF'
/dev/disk/by-partlabel/userdata / ext4 errors=remount-ro 0 1
tmpfs /tmp tmpfs defaults,nosuid 0 0
FSTABEOF

# User
useradd -m -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
usermod -aG sudo $USERNAME
echo "root:$USER_PASSWORD" | chpasswd

# Enable services
systemctl enable NetworkManager
systemctl enable ssh

# Serial consoles
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/serial-getty@ttyMSM0.service << 'UARTEOF'
[Unit]
Description=Serial Console ttyMSM0
[Service]
ExecStart=-/usr/sbin/agetty -L 115200 ttyMSM0 xterm-256color
Type=idle
Restart=always
[Install]
WantedBy=multi-user.target
UARTEOF
systemctl enable serial-getty@ttyMSM0.service

cat > /etc/systemd/system/serial-getty@ttyGS0.service << 'USBEOF'
[Unit]
Description=Serial Console ttyGS0 (USB)
[Service]
ExecStart=-/usr/sbin/agetty -L 115200 ttyGS0 xterm-256color
Type=idle
Restart=always
[Install]
WantedBy=multi-user.target
USBEOF
systemctl enable serial-getty@ttyGS0.service

# Module autoload
echo "g_serial" >> /etc/modules
cat > /etc/modules-load.d/razer-aura.conf << 'MODEOF'
g_serial
ath10k_snoc
rmi_i2c
MODEOF

# Auto-resize on first boot
cat > /etc/systemd/system/resizefs.service << 'RESIZEOF'
[Unit]
Description=Expand rootfs
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'resize2fs \$(findmnt -nvo SOURCE /)'
ExecStartPost=/bin/systemctl disable resizefs.service
RemainAfterExit=true
[Install]
WantedBy=default.target
RESIZEOF
systemctl enable resizefs.service

# Disable noisy timers
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true

apt clean
echo "System setup done."
SYSEOF
chmod +x $CHROOT_DIR/tmp/setup-system.sh
chroot $CHROOT_DIR /tmp/setup-system.sh

# Step 6: Install kernel modules
echo "[6/8] Installing kernel modules..."
rsync -a $OUTPUT/modules_install/lib/modules/$KVER $CHROOT_DIR/lib/modules/
chroot $CHROOT_DIR depmod -a $KVER

# Step 7: Install firmware (if available)
echo "[7/8] Installing firmware..."
if [ -d "$FIRMWARE_DIR" ] && [ "$(find $FIRMWARE_DIR -type f 2>/dev/null | head -1)" ]; then
    mkdir -p $CHROOT_DIR/usr/lib/firmware
    cp -rv $FIRMWARE_DIR/* $CHROOT_DIR/usr/lib/firmware/
    echo "  Firmware installed."
else
    echo "  WARNING: No firmware in $FIRMWARE_DIR - WiFi/GPU won't work"
    # Create placeholder dirs
    mkdir -p $CHROOT_DIR/usr/lib/firmware/{qcom/sdm845/Razer/aura,ath10k/WCN3990/hw1.0}
fi

# Step 8: Install KlipperScreen
echo "[8/8] Installing KlipperScreen..."
cat > $CHROOT_DIR/tmp/install-ks.sh << 'KSEOF'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# X11 + GTK deps
apt update
apt install -y xserver-xorg-core xinit xinput x11-xserver-utils \
    xserver-xorg-input-evdev xserver-xorg-input-libinput \
    xserver-xorg-video-fbdev xserver-xorg-legacy \
    python3-venv python3-dev python3-gi python3-gi-cairo \
    python3-cairo gir1.2-gtk-3.0 libgirepository1.0-dev \
    gcc libcairo2-dev pkg-config librsvg2-common \
    libopenjp2-7 libdbus-glib-1-dev git

# Clone KlipperScreen
cd /home/klipper
su -c "git clone --depth=1 https://github.com/KlipperScreen/KlipperScreen.git" klipper

# Python venv
su -c "python3 -m venv /home/klipper/.KlipperScreen-env" klipper
su -c "/home/klipper/.KlipperScreen-env/bin/pip install --upgrade pip" klipper
su -c "/home/klipper/.KlipperScreen-env/bin/pip install -r /home/klipper/KlipperScreen/scripts/KlipperScreen-requirements.txt" klipper

# Systemd service for auto-start
cat > /etc/systemd/system/xinit-klipperscreen.service << 'XEOF'
[Unit]
Description=KlipperScreen X11 Display
After=systemd-user-sessions.service network-online.target
Wants=network-online.target
[Service]
Type=simple
User=klipper
Environment=DISPLAY=:0
ExecStart=/usr/bin/xinit /home/klipper/.KlipperScreen-env/bin/python /home/klipper/KlipperScreen/screen.py -- :0 vt1 -keeptty -noreset
Restart=on-failure
RestartSec=5s
SupplementaryGroups=video input render tty
[Install]
WantedBy=multi-user.target
XEOF
systemctl enable xinit-klipperscreen.service

# X11 config
cat > /etc/X11/Xwrapper.config << 'XWEOF'
allowed_users=anybody
needs_root_rights=yes
XWEOF

# .xinitrc
cat > /home/klipper/.xinitrc << 'XIEOF'
#!/bin/sh
xset s off
xset -dpms
xset s noblank
exec /home/klipper/.KlipperScreen-env/bin/python /home/klipper/KlipperScreen/screen.py
XIEOF
chown klipper:klipper /home/klipper/.xinitrc
chmod +x /home/klipper/.xinitrc

# KlipperScreen config
mkdir -p /home/klipper/printer_data/config
cat > /home/klipper/printer_data/config/KlipperScreen.conf << 'KCEOF'
[main]
24htime: True
screen_blanking: off
moonraker_host: 127.0.0.1
moonraker_port: 7125
[printer Printer]
moonraker_host: 127.0.0.1
moonraker_port: 7125
KCEOF
chown -R klipper:klipper /home/klipper/printer_data

apt clean
echo "KlipperScreen installed."
KSEOF
chmod +x $CHROOT_DIR/tmp/install-ks.sh
chroot $CHROOT_DIR /tmp/install-ks.sh

# Final cleanup
echo "Cleaning up..."
chroot $CHROOT_DIR bash -c "apt clean; rm -rf /tmp/*"

umount $CHROOT_DIR/proc 2>/dev/null || true
umount $CHROOT_DIR/dev/pts 2>/dev/null || true
umount $CHROOT_DIR/dev 2>/dev/null || true
umount $CHROOT_DIR/sys 2>/dev/null || true
umount $CHROOT_DIR

# Zero free blocks so img2simg can skip them (critical for USB 2.0 flashing)
echo "Zeroing free blocks (zerofree)..."
if ! command -v zerofree &>/dev/null; then
    apt-get install -y zerofree
fi
umount $CHROOT_DIR 2>/dev/null || true
zerofree -v $ROOTFS_IMG

# Convert to sparse
echo "Creating sparse image..."
img2simg $ROOTFS_IMG $OUTPUT/rootfs-sparse.img

echo ""
echo "========================================"
echo " Rootfs complete!"
echo "========================================"
ls -lh $ROOTFS_IMG $OUTPUT/rootfs-sparse.img
echo ""
echo "User: $USERNAME / $USER_PASSWORD"
echo "Root: root / $USER_PASSWORD"
