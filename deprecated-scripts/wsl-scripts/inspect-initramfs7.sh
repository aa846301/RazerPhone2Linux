#!/bin/bash
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-inspect8
rm -rf "$WORK"; mkdir -p "$WORK"
unmkinitramfs "$INITRD" "$WORK" 2>/dev/null

echo "=== wait-for-root content ==="
cat "$WORK/usr/sbin/wait-for-root"

echo ""
echo "=== scripts/local mountroot function ==="
# Show the actual mountroot() function
awk '/^mountroot\(\)/,/^}/' "$WORK/scripts/local"

echo ""
echo "=== scripts/local-premount/fixrtc ==="
cat "$WORK/scripts/local-premount/fixrtc" 2>/dev/null | head -30

rm -rf "$WORK"
echo "=== DONE ==="
