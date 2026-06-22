#!/bin/bash
# Verify the Windows-side rootfs-sparse.img after img2simg conversion
set -e
SPARSE=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img
RAW=/home/dinochang/rootfs-verify.img
MNT=/home/dinochang/rootfs-verify-mnt

# Clean up stale
umount "$MNT" 2>/dev/null || true
rm -f "$RAW"
mkdir -p "$MNT"

echo "[1] Converting Windows sparse -> raw..."
simg2img "$SPARSE" "$RAW"
echo "  Raw size: $(stat -c%s "$RAW") bytes"

echo ""
echo "[2] Mounting..."
mount -o loop,ro "$RAW" "$MNT"
echo "  OK"

echo ""
echo "[3] /usr/lib/aarch64-linux-gnu/ file count:"
COUNT=$(ls "$MNT/usr/lib/aarch64-linux-gnu/" 2>/dev/null | wc -l)
echo "  $COUNT files"
if [ "$COUNT" -lt 100 ]; then
    echo "  *** WARNING: Expected ~1021 files, got $COUNT ***"
fi

echo ""
echo "[4] Key library chain:"
echo -n "  /sbin (symlink?): "
readlink "$MNT/sbin" 2>/dev/null || echo "NOT a symlink"

echo -n "  /usr/sbin/init: "
ls -la "$MNT/usr/sbin/init" 2>&1 | head -1

echo -n "  /usr/lib/systemd/systemd: "
file "$MNT/usr/lib/systemd/systemd" 2>&1 | grep -o 'ARM aarch64.*stripped' || echo "ERROR"

echo -n "  /usr/lib/ld-linux-aarch64.so.1: "
ls -la "$MNT/usr/lib/ld-linux-aarch64.so.1" 2>&1 | head -1

echo -n "  /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1: "
file "$MNT/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" 2>&1 | grep -o 'ARM aarch64.*' || echo "ERROR or MISSING"

echo -n "  /usr/lib/aarch64-linux-gnu/libc.so.6: "
ls "$MNT/usr/lib/aarch64-linux-gnu/libc.so.6" 2>/dev/null && echo "EXISTS" || echo "MISSING"

echo ""
echo "[5] /dev/console in rootfs:"
ls -la "$MNT/dev/console" 2>&1 || echo "  MISSING (will be created by udev at boot)"

echo ""
echo "[6] /dev directory content count:"
ls "$MNT/dev/" 2>/dev/null | wc -l

echo ""
umount "$MNT"
rm -f "$RAW"
echo "=== DONE ==="
