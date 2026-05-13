#!/bin/bash
# Read critical service file contents from both images
SPARSE=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img
GOOD=/home/dinochang/razorphone2linux/output/rootfs.img
TMP_RAW=/tmp/diag2-sparse.img
MNT=/tmp/diag2-sparse-mnt
MNT2=/tmp/diag2-good-mnt

mkdir -p "$MNT" "$MNT2"
umount "$MNT" 2>/dev/null || true
umount "$MNT2" 2>/dev/null || true
rm -f "$TMP_RAW"

simg2img "$SPARSE" "$TMP_RAW" 2>/dev/null
mount -o loop,ro "$TMP_RAW" "$MNT"
mount -o loop,ro "$GOOD" "$MNT2"

echo "=== [SPARSE] usb-gadget.service ==="
cat "$MNT/etc/systemd/system/usb-gadget.service" 2>/dev/null || echo NOT_FOUND
echo ""
echo "=== [SPARSE] serial-getty@ttyGS0.service (override) ==="
cat "$MNT/etc/systemd/system/serial-getty@ttyGS0.service" 2>/dev/null || echo NOT_FOUND
echo ""
echo "=== [SPARSE] serial-getty@ttyGS0.service.d/after-usb-gadget.conf ==="
cat "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf" 2>/dev/null || echo NOT_FOUND
echo ""
echo "=== [GOOD] usb-gadget.service ==="
cat "$MNT2/etc/systemd/system/usb-gadget.service" 2>/dev/null || echo NOT_FOUND
echo ""
echo "=== [GOOD] serial-getty@ttyGS0.service (override) ==="
cat "$MNT2/etc/systemd/system/serial-getty@ttyGS0.service" 2>/dev/null || echo NOT_FOUND
echo ""
echo "=== [GOOD] serial-getty@ttyGS0.service.d/ ==="
ls "$MNT2/etc/systemd/system/serial-getty@ttyGS0.service.d/" 2>/dev/null || echo NOT_FOUND

umount "$MNT" "$MNT2"
rm -f "$TMP_RAW"
