#!/bin/bash
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-inspect7
rm -rf "$WORK"; mkdir -p "$WORK"
unmkinitramfs "$INITRD" "$WORK" 2>/dev/null

echo "=== find wait-for-root ==="
find "$WORK" -name 'wait-for-root' 2>/dev/null || echo "NOT FOUND anywhere"

echo ""
echo "=== full /usr/bin listing ==="
ls "$WORK/usr/bin/" 2>/dev/null | head -30

echo ""
echo "=== full /usr/sbin listing ==="
ls "$WORK/usr/sbin/" 2>/dev/null | head -20

echo ""
echo "=== bin and sbin contents ==="
ls "$WORK/bin/" 2>/dev/null | head -10
ls "$WORK/sbin/" 2>/dev/null | head -10

echo ""
echo "=== udevadm location ==="
find "$WORK" -name 'udevadm' 2>/dev/null
find "$WORK" -name 'udevd' -o -name 'systemd-udevd' 2>/dev/null

echo ""
echo "=== local script full mountroot section ==="
grep -n '' "$WORK/scripts/local" | sed -n '50,130p'

rm -rf "$WORK"
echo "=== DONE ==="
