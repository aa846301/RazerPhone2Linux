#!/bin/bash
# Refresh an already-built rootfs image after kernel/script changes.
#
# This avoids a full debootstrap rebuild when only kernel modules,
# initramfs, or first-boot services changed.
#
# Usage:
#   sudo bash /mnt/c/repo/razorphone2linux/wsl-scripts/refresh-existing-rootfs.sh

set -euo pipefail

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
WIN_REPO="/mnt/c/repo/razorphone2linux"
WORKDIR="$REAL_HOME/razorphone2linux"
OUTPUT="$WORKDIR/output"
WIN_OUTPUT="$WIN_REPO/output"
MNT="$WORKDIR/rootfs/refresh-mnt"
QEMU_AARCH64="/usr/bin/qemu-aarch64-static"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: run with sudo."
    exit 1
fi

if [ -f "${ROOTFS_IMG_OVERRIDE:-}" ]; then
    ROOTFS_IMG="$ROOTFS_IMG_OVERRIDE"
elif [ -f "$OUTPUT/rootfs.img" ]; then
    ROOTFS_IMG="$OUTPUT/rootfs.img"
elif [ -f "$WORKDIR/rootfs/rootfs-noble.img" ]; then
    ROOTFS_IMG="$WORKDIR/rootfs/rootfs-noble.img"
else
    echo "ERROR: no rootfs image found at:"
    echo "  $WORKDIR/rootfs/rootfs-noble.img"
    echo "  $OUTPUT/rootfs.img"
    exit 1
fi

KERNEL_VERSION=$(ls "$OUTPUT/modules_install/lib/modules/" 2>/dev/null | head -n 1 || true)
if [ -z "$KERNEL_VERSION" ]; then
    echo "ERROR: no installed kernel modules in $OUTPUT/modules_install/lib/modules/"
    exit 1
fi

if [ ! -x "$QEMU_AARCH64" ]; then
    echo "ERROR: $QEMU_AARCH64 not found. Install qemu-user-static."
    exit 1
fi

cleanup() {
    set +e
    umount "$MNT/proc" 2>/dev/null
    umount "$MNT/dev/pts" 2>/dev/null
    umount "$MNT/dev" 2>/dev/null
    umount "$MNT/sys" 2>/dev/null
    umount "$MNT" 2>/dev/null
}
trap cleanup EXIT

echo "=== Refreshing rootfs ==="
echo "Rootfs: $ROOTFS_IMG"
echo "Kernel: $KERNEL_VERSION"

mkdir -p "$MNT"
mount -o loop,rw "$ROOTFS_IMG" "$MNT"

if [ ! -e "$MNT/lib/ld-linux-aarch64.so.1" ]; then
    echo "ERROR: selected image does not look like a complete arm64 rootfs:"
    echo "  missing /lib/ld-linux-aarch64.so.1"
    echo "Try: ROOTFS_IMG_OVERRIDE=$OUTPUT/rootfs.img sudo -E bash $WIN_REPO/wsl-scripts/refresh-existing-rootfs.sh"
    exit 1
fi

echo "[1/6] Syncing kernel modules..."
mkdir -p "$MNT/lib/modules"
rsync -a --delete \
    "$OUTPUT/modules_install/lib/modules/$KERNEL_VERSION" \
    "$MNT/lib/modules/"

echo "[2/6] Installing USB ACM gadget service..."
mkdir -p "$MNT/usr/local/bin" "$MNT/etc/systemd/system"
cat > "$MNT/usr/local/bin/usb-gadget-setup.sh" << 'GADGET_EOF'
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
chmod +x "$MNT/usr/local/bin/usb-gadget-setup.sh"

cat > "$MNT/etc/systemd/system/usb-gadget.service" << 'SERVICE_EOF'
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
SERVICE_EOF
mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/usb-gadget.service \
    "$MNT/etc/systemd/system/multi-user.target.wants/usb-gadget.service"

mkdir -p "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d"
cat > "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf" << 'DROPIN_EOF'
[Unit]
After=usb-gadget.service
Requires=usb-gadget.service
DROPIN_EOF

echo "[3/6] Updating module autoload list..."
mkdir -p "$MNT/etc/modules-load.d"
cat > "$MNT/etc/modules-load.d/razer-aura.conf" << 'MODULES_EOF'
# Razer Phone 2 kernel modules
msm
panel-novatek-nt36830
ath10k_snoc
rmi_i2c
MODULES_EOF

echo "[4/6] Regenerating initramfs in arm64 chroot..."
cp -f "$QEMU_AARCH64" "$MNT/usr/bin/qemu-aarch64-static"
mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    printf '%s' ':qemu-aarch64:M:0:\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:CF' \
        > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
fi
mount --bind /proc "$MNT/proc"
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount --bind /sys "$MNT/sys"
chroot "$MNT" /bin/bash -lc \
    "depmod -a '$KERNEL_VERSION' && update-initramfs -c -k '$KERNEL_VERSION'"

echo "[5/6] Exporting initramfs..."
mkdir -p "$OUTPUT" "$WIN_OUTPUT"
cp -f "$MNT/boot/initrd.img-$KERNEL_VERSION" "$OUTPUT/initrd.img-$KERNEL_VERSION"
cp -f "$MNT/boot/initrd.img-$KERNEL_VERSION" "$OUTPUT/initrd.img"
cp -f "$OUTPUT/initrd.img-$KERNEL_VERSION" "$WIN_OUTPUT/initrd.img-$KERNEL_VERSION"
cp -f "$OUTPUT/initrd.img" "$WIN_OUTPUT/initrd.img"

echo "[6/6] Rebuilding sparse image..."
sync
cleanup
trap - EXIT

if command -v img2simg >/dev/null 2>&1; then
    img2simg "$ROOTFS_IMG" "$OUTPUT/rootfs-sparse.img"
    cp -f "$OUTPUT/rootfs-sparse.img" "$WIN_OUTPUT/rootfs-sparse.img"
else
    echo "WARNING: img2simg not found; rootfs-sparse.img was not regenerated."
fi

echo "DONE"
echo "  initrd: $OUTPUT/initrd.img-$KERNEL_VERSION"
echo "  sparse: $OUTPUT/rootfs-sparse.img"
