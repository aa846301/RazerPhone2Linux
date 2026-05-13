#!/bin/bash
set -e
RAW=/tmp/rootfs-fix.img
MNT=/tmp/rootfs-fix-mnt
SPARSE=/home/dinochang/razorphone2linux/output/rootfs-sparse.img
GADGET_SCRIPT_SRC=/mnt/c/repo/razorphone2linux/wsl-scripts/usb-gadget-setup-ncm.sh

umount "$MNT" 2>/dev/null || true
rm -f "$RAW"
mkdir -p "$MNT"

echo "=== Converting sparse to raw ==="
simg2img "$SPARSE" "$RAW"
echo "Raw size: $(du -h "$RAW" | cut -f1)"

echo "=== Mounting ==="
mount -o loop "$RAW" "$MNT"

echo "=== Current usb-gadget script ==="
find "$MNT/usr/local/bin" -name "usb-gadget*" 2>/dev/null || echo "not found"
echo "RNDIS lines in current script:"
grep -n -i rndis "$MNT/usr/local/bin/usb-gadget-setup.sh" 2>/dev/null || echo "(none)"

echo "=== Installing fixed usb-gadget script ==="
cp "$GADGET_SCRIPT_SRC" "$MNT/usr/local/bin/usb-gadget-setup.sh"
chmod +x "$MNT/usr/local/bin/usb-gadget-setup.sh"
echo "RNDIS lines after fix:"
grep -n -i rndis "$MNT/usr/local/bin/usb-gadget-setup.sh" 2>/dev/null || echo "(none - RNDIS removed)"

echo "=== Confirming usb-gadget.service target ==="
cat "$MNT/etc/systemd/system/usb-gadget.service" 2>/dev/null | head -20 || echo "service not found"

echo "=== Unmounting ==="
umount "$MNT"
rm -f "$RAW"

echo "=== Re-sparsing ==="
RAW2=/tmp/rootfs-fix2.img
mount -o loop "$SPARSE" "$MNT" 2>/dev/null || true  # try direct sparse mount
# Actually, re-create the sparse from the modified raw
simg2img "$SPARSE" "$RAW2"
mount -o loop "$RAW2" "$MNT"
# Install the script
cp "$GADGET_SCRIPT_SRC" "$MNT/usr/local/bin/usb-gadget-setup.sh"
chmod +x "$MNT/usr/local/bin/usb-gadget-setup.sh"
umount "$MNT"

# Convert back to sparse
img2simg "$RAW2" "${SPARSE%.img}-fixed.img" 4096
rm -f "$RAW2"

ls -lh "${SPARSE%.img}-fixed.img"
echo "ROOTFS_FIX_DONE"
