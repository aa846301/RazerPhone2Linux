#!/bin/bash
# Inspect initramfs - find run-init and init script
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-inspect

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "[1] File type:"
file "$INITRD"

echo ""
echo "[2] Extracting initramfs..."
# Ubuntu initramfs may be gzip or zstd compressed cpio
if zstd -t "$INITRD" 2>/dev/null; then
    echo "  Format: zstd"
    zstd -d "$INITRD" -o /tmp/initrd.cpio
elif gunzip -t "$INITRD" 2>/dev/null; then
    echo "  Format: gzip"
    gunzip -c "$INITRD" > /tmp/initrd.cpio
else
    echo "  Format: unknown or multi-part, trying direct"
    cp "$INITRD" /tmp/initrd.cpio
fi

cd "$WORK"
cpio -id --no-preserve-owner < /tmp/initrd.cpio 2>&1 | tail -3
rm -f /tmp/initrd.cpio

echo ""
echo "[3] run-init location:"
find "$WORK" -name 'run-init' 2>/dev/null
for f in "$WORK/sbin/run-init" "$WORK/usr/sbin/run-init"; do
    if [ -f "$f" ]; then
        echo "  $f:"
        file "$f"
    fi
done

echo ""
echo "[4] init script - lines mentioning run-init or switch_root:"
grep -n 'run-init\|switch_root\|exec.*init\|sbin/init' "$WORK/init" 2>/dev/null | head -30 || echo "  init not found"

echo ""
echo "[5] Relevant section of init (last 50 lines before exec run-init):"
grep -n 'maybe_break\|run-init\|mount.*move\|/root/run\|exec ' "$WORK/init" 2>/dev/null | tail -30 || true

echo ""
echo "[6] /scripts/init-bottom contents:"
ls "$WORK/scripts/init-bottom/" 2>/dev/null || echo "  not found"

rm -rf "$WORK"
echo ""
echo "=== DONE ==="
