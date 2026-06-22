#!/bin/bash
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-inspect9
rm -rf "$WORK"; mkdir -p "$WORK"
unmkinitramfs "$INITRD" "$WORK" 2>/dev/null

echo "=== libudev in initramfs ==="
find "$WORK" -name 'libudev*' 2>/dev/null || echo "NOT FOUND"

echo ""
echo "=== local_mount_root function in scripts/local ==="
awk '/^local_mount_root\(\)/,/^}/' "$WORK/scripts/local"

echo ""
echo "=== resolve_device and get_fstype functions ==="
grep -n 'resolve_device\|get_fstype' "$WORK/scripts/functions" 2>/dev/null | head -20
grep -n 'resolve_device\|get_fstype' "$WORK/scripts/local" 2>/dev/null | head -20

echo ""
echo "=== usr/lib contents (shared libs) ==="
ls "$WORK/usr/lib/" 2>/dev/null | head -30
find "$WORK/usr/lib" -name '*.so*' 2>/dev/null | head -20

echo ""
echo "=== All .so files in initramfs ==="
find "$WORK" -name '*.so*' 2>/dev/null | grep -v '\.so\.' | head -5
find "$WORK" -name '*.so.*' 2>/dev/null | head -20

rm -rf "$WORK"
echo "=== DONE ==="
