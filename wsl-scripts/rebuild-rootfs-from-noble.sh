#!/bin/bash
# Rebuild sparse rootfs from original rootfs-noble.img
# Applies serial-getty fix, skips usb-gadget entirely
set -e

RAW=/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img
MNT=/home/dinochang/rootfs-noble-mnt
OUT_RAW=/home/dinochang/rootfs-fixed.img
OUT_SPARSE=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img

echo "=== Rebuild rootfs from clean source ==="
echo "Source: $RAW ($(stat -c%s "$RAW") bytes)"

# Clean up any stale mounts
umount "$MNT" 2>/dev/null || true

echo ""
echo "[1/5] Copying original image to working copy..."
cp --sparse=always "$RAW" "$OUT_RAW"
echo "  Copied: $(stat -c%s "$OUT_RAW") bytes"

echo ""
echo "[2/5] Mounting working copy rw..."
mkdir -p "$MNT"
mount -o loop,rw "$OUT_RAW" "$MNT"
echo "  Mounted at $MNT"

echo ""
echo "[3/5] Applying serial-getty fixes..."

# Remove usb-gadget.service drop-in for serial-getty (if exists)
if [ -d "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d" ]; then
    rm -rf "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d"
    echo "  Removed serial-getty drop-in"
else
    echo "  No serial-getty drop-in found (clean)"
fi

# Mask usb-gadget.service (conflicts with built-in g_serial)
ln -sf /dev/null "$MNT/etc/systemd/system/usb-gadget.service"
echo "  usb-gadget.service masked"

# Enable serial-getty@ttyGS0 independently
mkdir -p "$MNT/etc/systemd/system/getty.target.wants"
GETTY_LINK="$MNT/etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service"
if [ -L "$GETTY_LINK" ]; then
    echo "  serial-getty@ttyGS0 already enabled"
else
    ln -sf /lib/systemd/system/serial-getty@.service "$GETTY_LINK"
    echo "  serial-getty@ttyGS0 enabled"
fi

# Verify /run exists as a directory
if [ ! -d "$MNT/run" ]; then
    mkdir -p "$MNT/run"
    echo "  Created /run directory"
else
    echo "  /run directory OK"
fi

echo ""
echo "[4/5] Verifying critical binaries..."
echo -n "  /lib/systemd/systemd: "
file "$MNT/lib/systemd/systemd" | grep -o 'ARM aarch64.*' || echo "ERROR"
echo -n "  ld-linux-aarch64.so.1: "
ls "$MNT/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" > /dev/null 2>&1 && echo "OK" || echo "ERROR"
echo -n "  libc.so.6: "
ls "$MNT/usr/lib/aarch64-linux-gnu/libc.so.6" > /dev/null 2>&1 && echo "OK" || echo "ERROR"

echo ""
echo "[5/5] Unmounting and converting to sparse..."
umount "$MNT"
img2simg "$OUT_RAW" "$OUT_SPARSE"
rm -f "$OUT_RAW"
echo "  Done: $(ls -lh "$OUT_SPARSE" | awk '{print $5}')"

echo ""
echo "=== DONE ==="
echo "Flash with:"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
