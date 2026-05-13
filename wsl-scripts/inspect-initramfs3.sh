#!/bin/bash
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-extract2
rm -rf "$WORK"
mkdir -p "$WORK"

echo "=== unmkinitramfs ==="
unmkinitramfs "$INITRD" "$WORK"
echo "Done. Subdirs:"
ls "$WORK/"

echo ""
echo "=== find run-init ==="
find "$WORK" -name "run-init" 2>/dev/null

echo ""
echo "=== find init (top-level) ==="
find "$WORK" -maxdepth 3 -name "init" 2>/dev/null | head -10

echo ""
echo "=== sbin/lib/bin symlinks in each sub-extract ==="
for d in "$WORK"/*/; do
    echo "-- $d --"
    ls -la "$d/sbin" "$d/lib" "$d/bin" 2>/dev/null | head -5
done

echo ""
echo "=== init script lines (run-init + init= + console) ==="
for f in $(find "$WORK" -name "init" -type f 2>/dev/null); do
    echo "--- $f ---"
    grep -n 'run-init\|init=\|/dev/console\|switch_root' "$f" | head -30
done

echo ""
rm -rf "$WORK"
echo "=== DONE ==="
