#!/bin/bash
set -euo pipefail

WORKDIR=~/razorphone2linux
OUTPUT=$WORKDIR/output
KDIR=$WORKDIR/kernel/linux
KVER=$(ls $OUTPUT/modules_install/lib/modules/ | head -1)

echo '=== Creating boot.img ==='

# Step 1: Create minimal initramfs
echo '[1/3] Creating initramfs...'
INITRD_DIR=$(mktemp -d)
mkdir -p $INITRD_DIR/{dev,etc,lib,proc,sys,sysroot,run}

# Use static aarch64 init binary instead of busybox shell script
STATIC_INIT=$WORKDIR/initramfs/init-aarch64
if [ ! -f "$STATIC_INIT" ]; then
    echo "ERROR: $STATIC_INIT not found. Build it first with aarch64-linux-gnu-gcc."
    exit 1
fi
cp "$STATIC_INIT" $INITRD_DIR/init
chmod +x $INITRD_DIR/init

(cd $INITRD_DIR && find . | cpio -o -H newc 2>/dev/null | gzip) > $OUTPUT/initramfs.cpio.gz
rm -rf $INITRD_DIR
echo "  initramfs: $(du -h $OUTPUT/initramfs.cpio.gz | cut -f1)"

# Step 2: Create boot.img
echo '[2/3] Creating boot.img...'
CMDLINE="console=tty0 console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0xA84000 clk_ignore_unused pd_ignore_unused fw_devlink=permissive root=/dev/disk/by-partlabel/userdata rootfstype=ext4 rootwait rw loglevel=7 pcie_aspm=off"

python3 $WORKDIR/mkbootimg-tool/mkbootimg.py \
    --kernel $OUTPUT/Image.gz-dtb \
    --ramdisk $OUTPUT/initramfs.cpio.gz \
    --base 0x00000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --pagesize 4096 \
    --header_version 1 \
    --cmdline "$CMDLINE" \
    --os_version 14.0.0 \
    --os_patch_level 2024-01 \
    -o $OUTPUT/boot.img

echo "  boot.img: $(du -h $OUTPUT/boot.img | cut -f1)"

# Step 3: Create vbmeta
echo '[3/3] Creating vbmeta...'
python3 << 'PYEOF'
import struct
data = bytearray(4096)
data[0:4] = b'AVB0'
struct.pack_into('>I', data, 4, 1)
struct.pack_into('>I', data, 8, 1)
struct.pack_into('>I', data, 120, 3)
import os
outdir = os.path.expanduser('~/razorphone2linux/output')
with open(os.path.join(outdir, 'vbmeta_disabled.img'), 'wb') as f:
    f.write(bytes(data))
PYEOF
echo '  vbmeta_disabled.img created'

echo ''
echo '=== boot.img complete ==='
ls -lh $OUTPUT/boot.img $OUTPUT/vbmeta_disabled.img $OUTPUT/initramfs.cpio.gz
