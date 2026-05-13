#!/bin/bash
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-inspect5
rm -rf "$WORK"; mkdir -p "$WORK"
unmkinitramfs "$INITRD" "$WORK" 2>&1 | head -3

echo "=== run-init architecture ==="
file "$WORK/usr/bin/run-init"

echo ""
echo "=== /sbin and /lib at root - are they symlinks? ==="
ls -la "$WORK/sbin" "$WORK/lib" 2>/dev/null

echo ""
echo "=== init script lines 260-400 (mount + run-init section) ==="
sed -n '260,410p' "$WORK/init" 2>/dev/null

echo ""
echo "=== rootmnt variable ==="
grep -n 'rootmnt=' "$WORK/init" | head -10

echo ""
echo "=== mountroot script ==="
cat "$WORK/scripts/local" 2>/dev/null | head -80

rm -rf "$WORK"
echo "=== DONE ==="
