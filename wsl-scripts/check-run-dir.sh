#!/bin/bash
set -e
echo "=== Checking /run in Windows-side sparse image ==="
IMG=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img
RAW=/tmp/rootfs-run-verify.img
MNT=/home/dinochang/rootfs-run-verify-mnt

echo "[1] Converting sparse to raw..."
simg2img "$IMG" "$RAW"
echo "  Done"

echo ""
echo "[2] Mounting..."
mkdir -p "$MNT"
mount -o loop,ro "$RAW" "$MNT"
echo "  Mounted at $MNT"

echo ""
echo "[3] /run directory:"
ls -ld "$MNT/run" 2>/dev/null || echo "  /run MISSING!"
echo ""
echo "[4] /run contents:"
ls -la "$MNT/run/" 2>/dev/null | head -20 || echo "  /run is EMPTY or MISSING"

echo ""
echo "[5] Also check /sbin /lib /bin symlinks:"
ls -la "$MNT/sbin" "$MNT/lib" "$MNT/bin" 2>/dev/null

echo ""
echo "[6] /usr/sbin/init symlink:"
ls -la "$MNT/usr/sbin/init" 2>/dev/null

umount "$MNT"
rmdir "$MNT"
rm -f "$RAW"
echo ""
echo "=== DONE ==="
