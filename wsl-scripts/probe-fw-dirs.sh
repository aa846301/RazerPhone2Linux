#!/bin/bash
set -euo pipefail

mkdir -p /tmp/fw-out/dsp-mnt /tmp/fw-out/vendor-mnt

# Re-mount if not already mounted
mountpoint -q /tmp/fw-out/dsp-mnt    || mount -o ro,loop /tmp/fw-out/dsp-raw.img    /tmp/fw-out/dsp-mnt
mountpoint -q /tmp/fw-out/vendor-mnt || mount -o ro,loop /tmp/fw-out/vendor-raw.img /tmp/fw-out/vendor-mnt

echo "=== DSP adsp dir ==="
ls /tmp/fw-out/dsp-mnt/adsp/ 2>/dev/null | head -20

echo ""
echo "=== vendor top ==="
ls /tmp/fw-out/vendor-mnt/ | head -20

echo ""
echo "=== vendor firmware/ ==="
ls /tmp/fw-out/vendor-mnt/firmware/ 2>/dev/null | head -20 || echo "no firmware dir"

echo ""
echo "=== find a630 ==="
find /tmp/fw-out/vendor-mnt -name "a630*" 2>/dev/null | head -10

echo ""
echo "=== find WCN3990 ==="
find /tmp/fw-out/vendor-mnt -path "*WCN3990*" 2>/dev/null | head -10

echo ""
echo "=== find firmware-5.bin ==="
find /tmp/fw-out/vendor-mnt -name "firmware-5.bin" 2>/dev/null | head -10
