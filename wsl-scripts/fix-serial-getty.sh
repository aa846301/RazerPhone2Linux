#!/bin/bash
# fix-serial-getty.sh
# Remove the broken usb-gadget.service dependency from serial-getty@ttyGS0,
# and disable usb-gadget.service (which conflicts with the built-in g_serial
# gadget driver: CONFIG_USB_G_SERIAL=y already binds DWC3 UDC at boot).
#
# Root cause: CONFIG_USB_G_SERIAL=y (built-in) auto-creates ttyGS0.
# usb-gadget.service tries to bind ConfigFS ACM to the same UDC → EBUSY.
# The serial-getty drop-in had Requires=usb-gadget.service which could
# prevent getty from starting if usb-gadget.service failed.
#
# Run in WSL as: sudo bash /mnt/c/repo/razorphone2linux/wsl-scripts/fix-serial-getty.sh

set -e

WINDOWS_REPO="/mnt/c/repo/razorphone2linux"
SPARSE_IN="$WINDOWS_REPO/output/rootfs-sparse.img"
RAW_IMG="/tmp/rootfs-serial-fix.img"
MNT="/tmp/rootfs-serial-mnt"
SPARSE_OUT="$WINDOWS_REPO/output/rootfs-sparse.img"

echo "[1/5] Converting sparse → raw ext4..."
if ! command -v simg2img &>/dev/null; then
    apt-get install -y simg2img 2>/dev/null || \
    apt-get install -y android-tools-fsutils 2>/dev/null || true
fi
simg2img "$SPARSE_IN" "$RAW_IMG"
echo "  Raw image: $(du -h $RAW_IMG | cut -f1)"

echo "[2/5] Mounting raw ext4..."
mkdir -p "$MNT"
mount -o loop,rw "$RAW_IMG" "$MNT"
echo "  Mounted at $MNT"

echo "[3/5] Removing usb-gadget Requires dependency from serial-getty..."

# Remove the drop-in directory entirely — it contained:
#   [Unit]
#   After=usb-gadget.service
#   Requires=usb-gadget.service
# With CONFIG_USB_G_SERIAL=y (built-in), g_serial handles ttyGS0 automatically.
# No dependency on usb-gadget.service is needed or wanted.
DROPIN_DIR="$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d"
if [ -d "$DROPIN_DIR" ]; then
    echo "  Removing $DROPIN_DIR"
    rm -rf "$DROPIN_DIR"
else
    echo "  Drop-in dir not found (already clean)"
fi

echo "[4/5] Disabling usb-gadget.service (conflicts with built-in g_serial)..."

# Mask usb-gadget.service so it never starts
SYSTEMD_DIR="$MNT/etc/systemd/system"
mkdir -p "$SYSTEMD_DIR"
ln -sf /dev/null "$SYSTEMD_DIR/usb-gadget.service" 2>/dev/null || true
echo "  usb-gadget.service masked (→ /dev/null)"

# Ensure serial-getty@ttyGS0 is enabled so it starts when ttyGS0 appears
GETTY_WANTS="$MNT/etc/systemd/system/getty.target.wants"
mkdir -p "$GETTY_WANTS"
if [ ! -L "$GETTY_WANTS/serial-getty@ttyGS0.service" ]; then
    ln -sf /lib/systemd/system/serial-getty@.service \
        "$GETTY_WANTS/serial-getty@ttyGS0.service"
    echo "  serial-getty@ttyGS0.service enabled"
else
    echo "  serial-getty@ttyGS0.service already enabled"
fi

echo "[5/5] Converting back to sparse image..."
umount "$MNT"
rmdir "$MNT"
if command -v img2simg &>/dev/null; then
    img2simg "$RAW_IMG" "$SPARSE_OUT"
else
    echo "  img2simg not found, copying raw image as-is (fastboot can handle it)"
    cp "$RAW_IMG" "$SPARSE_OUT"
fi
rm -f "$RAW_IMG"
echo "  Done: $(du -h $SPARSE_OUT | cut -f1)"

echo ""
echo "=== fix-serial-getty.sh complete ==="
echo "Now flash:"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
