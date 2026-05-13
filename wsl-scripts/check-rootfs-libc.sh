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
echo '[3] libc6 dpkg status:'
grep -A5 '^Package: libc6$' "$MNT/var/lib/dpkg/status" 2>/dev/null | head -10 || echo '  NOT FOUND in dpkg'

echo ''
echo '[4] /usr/lib/aarch64-linux-gnu/ full listing:'
ls -la "$MNT/usr/lib/aarch64-linux-gnu/" 2>&1

echo ''
echo '[5] /usr/lib/ top-level (first 30):'
ls "$MNT/usr/lib/" 2>&1 | head -30

echo ''
echo '[6] Does ld-linux exist anywhere?'
find "$MNT/usr/lib/" -name 'ld-linux*' 2>/dev/null || echo '  NOT FOUND'
find "$MNT/lib/" -maxdepth 2 -name 'ld-linux*' 2>/dev/null || echo '  NOT FOUND in /lib'

echo ''
umount "$MNT"
rm -f "$RAW"
echo '=== DONE ==='
