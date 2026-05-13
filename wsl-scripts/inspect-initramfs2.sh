#!/bin/bash
# Properly extract Ubuntu Noble initramfs (handles multi-part microcode+zstd)
set -e
INITRD=/home/dinochang/razorphone2linux/output/initrd.img-6.16.0-rc2-sdm845-ged6098a37a4c-dirty
WORK=/home/dinochang/initrd-extract

rm -rf "$WORK"
mkdir -p "$WORK"

echo "[1] initrd file info:"
ls -lh "$INITRD"
file "$INITRD"

echo ""
echo "[2] Trying unmkinitramfs (preferred)..."
if command -v unmkinitramfs >/dev/null 2>&1; then
    unmkinitramfs "$INITRD" "$WORK"
    echo "  unmkinitramfs OK"
else
    echo "  unmkinitramfs not found, using manual extraction"
    # Ubuntu Noble: may be plain zstd cpio or microcode prepended
    # Try zstdcat directly
    if zstdcat "$INITRD" > /tmp/initrd.cpio 2>/dev/null; then
        echo "  Format: plain zstd"
        cd "$WORK" && cpio -id --no-preserve-owner < /tmp/initrd.cpio
    else
        # Try skipcpio approach: find zstd magic bytes offset
        echo "  Trying offset search for zstd magic..."
        python3 -c "
import sys
data = open('$INITRD','rb').read()
magic = b'\x28\xb5\x2f\xfd'
idx = data.find(magic)
if idx < 0:
    print('zstd magic not found')
    sys.exit(1)
print(f'  zstd starts at offset {idx}')
open('/tmp/initrd-zstd.raw','wb').write(data[idx:])
"
        cd "$WORK" && zstdcat /tmp/initrd-zstd.raw | cpio -id --no-preserve-owner
        rm -f /tmp/initrd-zstd.raw
    fi
    rm -f /tmp/initrd.cpio
fi

echo ""
echo "[3] run-init binary:"
if [ -f "$WORK/sbin/run-init" ]; then
    file "$WORK/sbin/run-init"
elif [ -f "$WORK/usr/sbin/run-init" ]; then
    file "$WORK/usr/sbin/run-init"
else
    find "$WORK" -name 'run-init' 2>/dev/null | head -5
    echo "  NOT FOUND"
fi

echo ""
echo "[4] init binary / script:"
file "$WORK/init" 2>/dev/null || echo "  not found"

echo ""
echo "[5] Init script - run-init call and surrounding logic:"
grep -n 'run.init\|switch_root\|exec.*init\|/root/run\|maybe_break\|init=' "$WORK/init" 2>/dev/null | tail -40

echo ""
echo "[6] scripts/init-bottom contents:"
ls "$WORK/scripts/init-bottom/" 2>/dev/null | head -20 || echo "  not found"

echo ""
echo "[7] Any usrmerge or sbin symlink in initramfs:"
ls -la "$WORK/sbin" 2>/dev/null || echo "  /sbin not found"
ls -la "$WORK/lib" 2>/dev/null | head -3 || echo "  /lib not found"

rm -rf "$WORK"
echo ""
echo "=== DONE ==="
