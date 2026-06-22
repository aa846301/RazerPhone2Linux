#!/bin/bash
# recover-rootfs-build.sh
# Recovery script for rootfs build that failed at step [8/10] due to disk full.
# Resumes from dpkg recovery -> KlipperScreen deps -> KlipperScreen install -> image creation.
# Must be run as root (or via sudo).

set -euo pipefail

WORKDIR="/home/dinochang/razorphone2linux"
CHROOT_DIR="$WORKDIR/rootfs/chroot"
ROOTFS_IMG="$WORKDIR/rootfs/rootfs-noble.img"
OUTPUT_DIR="$WORKDIR/output"
WIN_OUTPUT_DIR="/mnt/c/repo/razorphone2linux/output"

echo "========================================"
echo " Rootfs Build Recovery"
echo "========================================"

# -------------------------------------------------------
# Step R1: Mount image and virtual filesystems
# -------------------------------------------------------
echo "[R1] Mounting rootfs image..."
mkdir -p "$CHROOT_DIR"
mount -o loop "$ROOTFS_IMG" "$CHROOT_DIR"
df -h "$CHROOT_DIR"

# Mount virtual filesystems
mount --bind /proc "$CHROOT_DIR/proc"
mount --bind /sys "$CHROOT_DIR/sys"
mount --bind /dev "$CHROOT_DIR/dev"
mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
echo "  Mounts OK."

# Ensure qemu is present
if [ -f /usr/bin/qemu-aarch64-static ]; then
    cp /usr/bin/qemu-aarch64-static "$CHROOT_DIR/usr/bin/qemu-aarch64-static"
fi

# Cleanup function to ensure unmount on exit
cleanup() {
    echo "  Unmounting filesystems..."
    umount "$CHROOT_DIR/proc"    2>/dev/null || true
    umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    umount "$CHROOT_DIR/dev"     2>/dev/null || true
    umount "$CHROOT_DIR/sys"     2>/dev/null || true
    umount "$CHROOT_DIR"         2>/dev/null || true
}
trap cleanup EXIT

# -------------------------------------------------------
# Step R2: Fix dpkg state
# -------------------------------------------------------
echo "[R2] Fixing dpkg state..."
chroot "$CHROOT_DIR" bash -c '
# Remove stale dpkg lock/temp files
rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/updates/tmp.i
rm -f /var/cache/apt/archives/lock
# Remove failed partial packages from apt cache
rm -f /tmp/apt-dpkg-install-*/* 2>/dev/null || true
rmdir /tmp/apt-dpkg-install-* 2>/dev/null || true
# Clean apt cache to free space
apt clean
# Remove any downloaded but not yet installed .deb files
rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb 2>/dev/null || true
# Configure any half-configured packages
dpkg --configure -a --force-all 2>&1 | tail -20 || true
echo "  dpkg state fixed."
'

# -------------------------------------------------------
# Step R3: Free space check
# -------------------------------------------------------
echo "[R3] Checking available space..."
df -h "$CHROOT_DIR"

# -------------------------------------------------------
# Step R4: Fix broken packages (partial installs from disk-full)
# -------------------------------------------------------
echo "[R4] Running apt --fix-broken install to complete partial packages..."
chroot "$CHROOT_DIR" bash -c '
export DEBIAN_FRONTEND=noninteractive
# Remove any .deb in partial that may be corrupt
rm -f /var/cache/apt/archives/partial/*.deb 2>/dev/null || true
apt --fix-broken install -y 2>&1 | tail -30 || true
echo "  fix-broken complete."
'
echo "[R4] Space after fix-broken:"
df -h "$CHROOT_DIR"

# -------------------------------------------------------
# Step 8 (retry): Install KlipperScreen dependencies
# -------------------------------------------------------
echo "[8/10] Installing KlipperScreen dependencies (retry)..."
cat > "$CHROOT_DIR/tmp/install-klipperscreen-deps.sh" << 'KS_EOF'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

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
    autoconf \
    git \
    python3-pip

apt clean
rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb 2>/dev/null || true
echo "KlipperScreen deps installed."
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

# Create X11 auto-start service
cat > /etc/systemd/system/xinit-klipperscreen.service << 'XINIT_EOF'
[Unit]
Description=X11 Display Server for KlipperScreen
After=systemd-user-sessions.service
Wants=network-online.target

[Service]
Type=simple
User=klipper
Environment="DISPLAY=:0"
ExecStart=/usr/bin/xinit /home/klipper/.KlipperScreen-env/bin/python /home/klipper/KlipperScreen/screen.py -- :0 vt1 -keeptty -noreset -dpms
Restart=on-failure
RestartSec=5s
SupplementaryGroups=video input render tty

[Install]
WantedBy=multi-user.target
XINIT_EOF

systemctl enable xinit-klipperscreen.service

# Configure X11
cat > /etc/X11/Xwrapper.config << 'XWRAP_EOF'
allowed_users=anybody
needs_root_rights=yes
XWRAP_EOF

# Configure xinitrc
mkdir -p "$KS_HOME/.xinitrc.d"
cat > "$KS_HOME/.xinitrc" << 'XINITRC_EOF'
#!/bin/sh
xset s off
xset -dpms
xset s noblank
exec /home/klipper/.KlipperScreen-env/bin/python /home/klipper/KlipperScreen/screen.py
XINITRC_EOF
chown "$KS_USER:$KS_USER" "$KS_HOME/.xinitrc"
chmod +x "$KS_HOME/.xinitrc"

# Create default KlipperScreen config
mkdir -p "$KS_HOME/printer_data/config"
cat > "$KS_HOME/printer_data/config/KlipperScreen.conf" << 'KSCONF_EOF'
[main]
24htime: True
screen_blanking: off
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
echo "  KlipperScreen installed."

# -------------------------------------------------------
# Step 10: Cleanup and create sparse image
# -------------------------------------------------------
echo "[10/10] Final cleanup and creating sparse image..."

# Final cleanup inside chroot
chroot "$CHROOT_DIR" bash -c "apt clean && rm -rf /tmp/* && rm -f /var/cache/apt/archives/*.deb"

# Unmount (trap will also run, but we do it explicitly first)
umount "$CHROOT_DIR/proc"    2>/dev/null || true
umount "$CHROOT_DIR/dev/pts" 2>/dev/null || true
umount "$CHROOT_DIR/dev"     2>/dev/null || true
umount "$CHROOT_DIR/sys"     2>/dev/null || true
umount "$CHROOT_DIR"
trap - EXIT   # Disable cleanup trap (already unmounted)

# Zerofree to minimize sparse image size
echo "  Zeroing free ext4 blocks (zerofree)..."
if ! command -v zerofree &>/dev/null; then
    apt-get install -y zerofree
fi
zerofree -v "$ROOTFS_IMG"
echo "  zerofree complete."

# Create Android sparse image
mkdir -p "$OUTPUT_DIR"
SPARSE_IMG="$OUTPUT_DIR/rootfs-sparse.img"
OUTPUT_ROOTFS_IMG="$OUTPUT_DIR/rootfs.img"

img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
cp -f "$ROOTFS_IMG" "$OUTPUT_ROOTFS_IMG"

# Copy to Windows
mkdir -p "$WIN_OUTPUT_DIR"
cp -f "$OUTPUT_ROOTFS_IMG" "$WIN_OUTPUT_DIR/rootfs.img"
cp -f "$SPARSE_IMG" "$WIN_OUTPUT_DIR/rootfs-sparse.img"

echo ""
echo "========================================"
echo " Recovery complete!"
echo "========================================"
SPARSE_SIZE=$(du -sh "$WIN_OUTPUT_DIR/rootfs-sparse.img" | cut -f1)
RAW_SIZE=$(du -sh "$WIN_OUTPUT_DIR/rootfs.img" | cut -f1)
echo "  Sparse image: $WIN_OUTPUT_DIR/rootfs-sparse.img ($SPARSE_SIZE)"
echo "  Raw image:    $WIN_OUTPUT_DIR/rootfs.img ($RAW_SIZE)"
echo ""
echo "Next: Run bash scripts/04-make-boot-image.sh"
