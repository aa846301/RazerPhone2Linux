#!/bin/bash
# Diagnose what the other AI broke in the rootfs images
set -e

SPARSE=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img
GOOD=/home/dinochang/razorphone2linux/output/rootfs.img
TMP_RAW=/tmp/diag-sparse.img
MNT_SPARSE=/tmp/diag-sparse-mnt
MNT_GOOD=/tmp/diag-good-mnt

mkdir -p "$MNT_SPARSE" "$MNT_GOOD"
umount "$MNT_SPARSE" 2>/dev/null || true
umount "$MNT_GOOD" 2>/dev/null || true
rm -f "$TMP_RAW"

echo "=== Converting sparse -> raw ==="
simg2img "$SPARSE" "$TMP_RAW"
echo "Done: $(du -sh $TMP_RAW | cut -f1)"

echo ""
echo "=== Mounting both images ==="
mount -o loop,ro "$TMP_RAW" "$MNT_SPARSE"
mount -o loop,ro "$GOOD" "$MNT_GOOD"

echo ""
echo "============================================================"
echo "  CURRENT rootfs-sparse.img (OTHER AI VERSION)"
echo "============================================================"

echo ""
echo "[usb-gadget.service]"
ls -la "$MNT_SPARSE/etc/systemd/system/usb-gadget.service" 2>/dev/null && \
    readlink -f "$MNT_SPARSE/etc/systemd/system/usb-gadget.service" 2>/dev/null || echo "  NOT PRESENT (good - no mask)"

echo ""
echo "[serial-getty@ttyGS0 symlinks]"
ls -la "$MNT_SPARSE/etc/systemd/system/getty.target.wants/" 2>/dev/null | grep -i serial || echo "  NOT in getty.target.wants"
ls -la "$MNT_SPARSE/etc/systemd/system/multi-user.target.wants/" 2>/dev/null | grep -i serial || echo "  NOT in multi-user.target.wants"
ls -la "$MNT_SPARSE/etc/systemd/system/serial-getty@ttyGS0.service.d/" 2>/dev/null || echo "  NO serial-getty drop-in dir"

echo ""
echo "[usb-gadget.service target]"
ls -la "$MNT_SPARSE/lib/systemd/system/usb-gadget.service" 2>/dev/null || \
    ls -la "$MNT_SPARSE/usr/lib/systemd/system/usb-gadget.service" 2>/dev/null || echo "  No usb-gadget.service unit file in lib"

echo ""
echo "[/etc/systemd/system/ custom entries]"
ls -la "$MNT_SPARSE/etc/systemd/system/" 2>/dev/null | grep -v '^total\|^\.\|^dr' | head -30

echo ""
echo "[modules dir]"
ls -1 "$MNT_SPARSE/lib/modules/" 2>/dev/null

echo ""
echo "============================================================"
echo "  ORIGINAL output/rootfs.img (OUR SESSION BUILD)"
echo "============================================================"

echo ""
echo "[usb-gadget.service]"
ls -la "$MNT_GOOD/etc/systemd/system/usb-gadget.service" 2>/dev/null && \
    readlink -f "$MNT_GOOD/etc/systemd/system/usb-gadget.service" 2>/dev/null || echo "  NOT PRESENT (good - no mask)"

echo ""
echo "[serial-getty@ttyGS0 symlinks]"
ls -la "$MNT_GOOD/etc/systemd/system/getty.target.wants/" 2>/dev/null | grep -i serial || echo "  NOT in getty.target.wants"
ls -la "$MNT_GOOD/etc/systemd/system/multi-user.target.wants/" 2>/dev/null | grep -i serial || echo "  NOT in multi-user.target.wants"

echo ""
echo "[/etc/systemd/system/ custom entries]"
ls -la "$MNT_GOOD/etc/systemd/system/" 2>/dev/null | grep -v '^total\|^\.\|^dr' | head -30

echo ""
echo "[modules dir]"
ls -1 "$MNT_GOOD/lib/modules/" 2>/dev/null

echo ""
echo "============================================================"
umount "$MNT_SPARSE" "$MNT_GOOD"
rm -f "$TMP_RAW"
echo "DONE"
