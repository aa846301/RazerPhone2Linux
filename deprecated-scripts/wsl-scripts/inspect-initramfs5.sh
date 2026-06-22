#!/bin/bash
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-inspect6
rm -rf "$WORK"; mkdir -p "$WORK"
unmkinitramfs "$INITRD" "$WORK" 2>/dev/null

echo "=== scripts/init-top ==="
ls "$WORK/scripts/init-top/" 2>/dev/null || echo "EMPTY/MISSING"

echo ""
echo "=== scripts/init-premount ==="
ls "$WORK/scripts/init-premount/" 2>/dev/null || echo "EMPTY/MISSING"

echo ""
echo "=== scripts/init-bottom ==="
ls "$WORK/scripts/init-bottom/" 2>/dev/null || echo "EMPTY/MISSING"

echo ""
echo "=== udev init-top script ==="
cat "$WORK/scripts/init-top/udev" 2>/dev/null || echo "NOT FOUND"

echo ""
echo "=== wait-for-root binary/script ==="
file "$WORK/usr/bin/wait-for-root" 2>/dev/null || \
file "$WORK/sbin/wait-for-root" 2>/dev/null || \
file "$WORK/bin/wait-for-root" 2>/dev/null || \
echo "NOT FOUND"
grep -r 'wait-for-root\|wait_for_root' "$WORK/scripts/" 2>/dev/null | head -10

echo ""
echo "=== rootfs /run directory check ==="
NOBLE=/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img
MNT=/home/dinochang/rootfs-run-mnt
mkdir -p "$MNT"
mount -o loop,ro "$NOBLE" "$MNT"
echo "  /run:"
ls -ld "$MNT/run" 2>/dev/null || echo "  /run MISSING!"
echo "  /run contents (count):"
ls "$MNT/run/" 2>/dev/null | wc -l
echo "  /run first few entries:"
ls "$MNT/run/" 2>/dev/null | head -5
umount "$MNT"
rmdir "$MNT"

rm -rf "$WORK"
echo ""
echo "=== DONE ==="
