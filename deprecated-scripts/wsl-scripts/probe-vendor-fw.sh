#!/bin/bash
mountpoint -q /tmp/fw-out/vendor-mnt 2>/dev/null || \
    sudo mount -o ro,loop /tmp/fw-out/vendor-raw.img /tmp/fw-out/vendor-mnt

echo "=== vendor/firmware/ ==="
ls /tmp/fw-out/vendor-mnt/firmware/ 2>/dev/null | head -30

echo ""
echo "=== vendor/firmware_mnt/ ==="
ls /tmp/fw-out/vendor-mnt/firmware_mnt/ 2>/dev/null | head -30

echo ""
echo "=== find a630 anywhere in vendor ==="
find /tmp/fw-out/vendor-mnt -iname "*a630*" 2>/dev/null | head -10

echo ""
echo "=== find ath10k in vendor ==="
find /tmp/fw-out/vendor-mnt -iname "*ath10k*" -o -iname "*WCN3990*" 2>/dev/null | head -10

echo ""
echo "=== vendor/etc/firmware/ ==="
ls /tmp/fw-out/vendor-mnt/etc/firmware/ 2>/dev/null | head -20

echo ""
echo "=== vendor/dsp/ ==="
ls /tmp/fw-out/vendor-mnt/dsp/ 2>/dev/null | grep -i "mbn\|adsp\|cdsp" | head -20
