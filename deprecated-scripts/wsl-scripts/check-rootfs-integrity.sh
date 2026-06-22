#!/bin/bash
set -e
SPARSE=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img
RAW=/home/dinochang/rootfs-check.img
MNT=/home/dinochang/rootfs-check-mnt

rm -f "$RAW"
mkdir -p "$MNT"

echo '[1] Converting sparse...'
simg2img "$SPARSE" "$RAW"
echo "  size: $(stat -c%s "$RAW") bytes"

echo '[2] Mounting...'
mount -o loop,ro "$RAW" "$MNT"
echo '  mounted OK'

echo ''
echo '[3] /run directory:'
if [ -d "$MNT/run" ]; then
    echo "  EXISTS ($(ls "$MNT/run" | wc -l) entries)"
else
    echo '  *** MISSING! ***'
fi

echo ''
echo '[4] /sbin/init:'
ls -la "$MNT/sbin/init" 2>&1 || echo '  *** MISSING ***'

echo ''
echo '[5] ELF arch of /lib/systemd/systemd:'
file "$MNT/lib/systemd/systemd" 2>&1

echo ''
echo '[6] ELF interpreter of systemd:'
readelf -l "$MNT/lib/systemd/systemd" 2>/dev/null | grep -i 'interpreter' || echo '  none/error'

echo ''
echo '[7] ARM64 dynamic linker:'
if [ -f "$MNT/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" ]; then
    ls -la "$MNT/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1"
else
    echo '  *** MISSING: /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 ***'
fi

echo ''
echo '[8] libc.so.6:'
if [ -f "$MNT/lib/aarch64-linux-gnu/libc.so.6" ]; then
    file "$MNT/lib/aarch64-linux-gnu/libc.so.6"
else
    echo '  *** MISSING ***'
fi

echo ''
echo '[9] /lib/aarch64-linux-gnu file count:'
ls "$MNT/lib/aarch64-linux-gnu/" 2>/dev/null | wc -l || echo '  dir missing'

echo ''
echo '[10] Top-level dirs in rootfs:'
ls "$MNT/"

echo ''
echo '[11] /etc/os-release:'
cat "$MNT/etc/os-release" 2>/dev/null || echo '  MISSING'

echo ''
umount "$MNT"
rm -f "$RAW"
echo '=== DONE ==='
