#!/bin/bash
set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
OUTPUT_DIR="$WORKDIR/output"
WIN_OUTPUT_DIR="/mnt/c/repo/razorphone2linux/output"
LOCAL_MKBOOTIMG="$WORKDIR/mkbootimg-tool/mkbootimg.py"
INIT_TEMPLATE="/mnt/c/repo/razorphone2linux/initramfs/init-debug.sh"
LOCAL_BUSYBOX_DEB="/mnt/c/repo/razorphone2linux/busybox-static_1%3a1.36.1-6ubuntu3.1_arm64.deb"
PREFERRED_BUSYBOX="$WORKDIR/output/debug/busybox-aarch64"
LOCAL_BUSYBOX_BIN="$OUTPUT_DIR/busybox-aarch64"
BOOT_IMG="$OUTPUT_DIR/boot-observable.img"
RAMDISK="$OUTPUT_DIR/initramfs-observable.cpio.gz"
VBMETA="$OUTPUT_DIR/vbmeta_disabled.img"
ROOTFS_SPARSE_IMG="$OUTPUT_DIR/rootfs-sparse.img"
DEBUG_STAY_INITRAMFS="${DEBUG_STAY_INITRAMFS:-1}"

echo '========================================'
echo ' Razer Phone 2 - Observable Boot Image '
echo '========================================'

if [ -f "$LOCAL_MKBOOTIMG" ]; then
    MKBOOTIMG_CMD=(python3 "$LOCAL_MKBOOTIMG")
elif command -v mkbootimg &>/dev/null; then
    MKBOOTIMG_CMD=(mkbootimg)
else
    echo "ERROR: mkbootimg tool not found."
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/Image.gz" ] || [ ! -f "$OUTPUT_DIR/sdm845-razer-aura.dtb" ]; then
    echo 'ERROR: mainline kernel artifacts missing in output/'
    echo 'Run scripts/02-build-kernel.sh first.'
    exit 1
fi

if [ ! -f "$INIT_TEMPLATE" ]; then
    echo "ERROR: debug init template not found at $INIT_TEMPLATE"
    exit 1
fi

copy_if_arm64_busybox() {
    local candidate="$1"

    [ -f "$candidate" ] || return 1
    if file "$candidate" | grep -q 'ARM aarch64'; then
        cp -f "$candidate" "$LOCAL_BUSYBOX_BIN"
        chmod +x "$LOCAL_BUSYBOX_BIN"
        return 0
    fi

    return 1
}

extract_arm64_busybox() {
    local pkg_dir extract_dir deb_path busybox_path

    pkg_dir=$(mktemp -d)
    extract_dir=$(mktemp -d)

    if [ -f "$LOCAL_BUSYBOX_DEB" ]; then
        cp "$LOCAL_BUSYBOX_DEB" "$pkg_dir/"
    fi

    deb_path=$(find "$pkg_dir" -maxdepth 1 -name 'busybox-static_*_arm64.deb' | head -n 1)
    if [ -z "$deb_path" ]; then
        echo 'ERROR: no arm64 busybox package available.'
        echo "Expected $LOCAL_BUSYBOX_DEB or a previously built busybox-aarch64."
        rm -rf "$pkg_dir" "$extract_dir"
        return 1
    fi

    dpkg-deb -x "$deb_path" "$extract_dir"
    busybox_path=$(find "$extract_dir" -path '*/bin/busybox' | head -n 1)
    if [ -z "$busybox_path" ]; then
        echo 'ERROR: arm64 busybox binary not found in package.'
        rm -rf "$pkg_dir" "$extract_dir"
        return 1
    fi

    cp "$busybox_path" "$LOCAL_BUSYBOX_BIN"
    chmod +x "$LOCAL_BUSYBOX_BIN"
    rm -rf "$pkg_dir" "$extract_dir"
}

echo '[1/4] Preparing kernel + DTB...'
cat "$OUTPUT_DIR/Image.gz" "$OUTPUT_DIR/sdm845-razer-aura.dtb" > "$OUTPUT_DIR/Image.gz-dtb"
echo "  Created Image.gz-dtb ($(du -h "$OUTPUT_DIR/Image.gz-dtb" | cut -f1))"

echo '[2/4] Preparing arm64 busybox + debug initramfs...'
mkdir -p "$OUTPUT_DIR" "$WIN_OUTPUT_DIR"

if ! copy_if_arm64_busybox "$PREFERRED_BUSYBOX" && ! copy_if_arm64_busybox "$LOCAL_BUSYBOX_BIN"; then
    extract_arm64_busybox
fi

INITRD_DIR=$(mktemp -d)
mkdir -p "$INITRD_DIR"/{bin,dev,etc,proc,run,sbin,sys,sysroot,tmp,usr/bin,usr/sbin}
cp "$LOCAL_BUSYBOX_BIN" "$INITRD_DIR/bin/busybox"
chmod +x "$INITRD_DIR/bin/busybox"
cp "$INIT_TEMPLATE" "$INITRD_DIR/init"
chmod +x "$INITRD_DIR/init"

for applet in sh mount umount switch_root sleep ls cat echo dmesg grep cut mkdir mknod ln readlink uname basename tr rm ifconfig route ps stty; do
    ln -sf busybox "$INITRD_DIR/bin/$applet"
done

(cd "$INITRD_DIR" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9) > "$RAMDISK"
rm -rf "$INITRD_DIR"
echo "  Created observable initramfs ($(du -h "$RAMDISK" | cut -f1))"

echo '[3/4] Creating observable boot image...'
# console parameter order rationale:
#   1. earlycon – hardware UART, works from very first printk (before drivers load)
#   2. ttyGS0   – USB ACM gadget, our primary debug channel (set up in initramfs)
#   3. ttyMSM0  – hardware UART tty, fallback if USB gadget is not available
#
# The Android ABL on Razer Phone 2 injects "console=null earlycon=null" which
# suppresses ttyMSM0 early output.  Listing ttyGS0 early ensures it still
# receives all messages once the USB gadget is up in initramfs.
# log_buf_len=4M retains messages that arrive before any console is ready.
CMDLINE='earlycon=msm_geni_serial,0xA84000 console=ttyGS0,115200n8 console=ttyMSM0,115200n8 keep_bootcon no_console_suspend initcall_debug clk_ignore_unused pd_ignore_unused fw_devlink=permissive root=/dev/disk/by-partlabel/userdata rootfstype=ext4 rootwait rw loglevel=8 ignore_loglevel printk.devkmsg=on panic=-1 log_buf_len=4M'

if [ "$DEBUG_STAY_INITRAMFS" = "1" ]; then
    CMDLINE="$CMDLINE debug_stay_initramfs=1"
fi

"${MKBOOTIMG_CMD[@]}" \
    --kernel "$OUTPUT_DIR/Image.gz-dtb" \
    --ramdisk "$RAMDISK" \
    --base 0x00000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --pagesize 4096 \
    --header_version 1 \
    --cmdline "$CMDLINE" \
    --os_version 14.0.0 \
    --os_patch_level 2024-01 \
    -o "$BOOT_IMG"

echo "  Created boot-observable.img ($(du -h "$BOOT_IMG" | cut -f1))"

echo '[4/4] Syncing observable artifacts...'
python3 - << 'PYEOF'
import os
import struct

outdir = os.path.expanduser('~/razorphone2linux/output')
data = bytearray(4096)
data[0:4] = b'AVB0'
struct.pack_into('>I', data, 4, 1)
struct.pack_into('>I', data, 8, 1)
struct.pack_into('>I', data, 120, 3)

with open(os.path.join(outdir, 'vbmeta_disabled.img'), 'wb') as handle:
    handle.write(data)
PYEOF

cp -f "$BOOT_IMG" "$WIN_OUTPUT_DIR/boot-observable.img"
cp -f "$RAMDISK" "$WIN_OUTPUT_DIR/initramfs-observable.cpio.gz"
cp -f "$VBMETA" "$WIN_OUTPUT_DIR/vbmeta_disabled.img"
cp -f "$LOCAL_BUSYBOX_BIN" "$WIN_OUTPUT_DIR/busybox-aarch64"

echo ''
echo '========================================'
echo ' Observable boot image complete!'
echo '========================================'
ls -lh "$BOOT_IMG" "$RAMDISK" "$VBMETA"
echo ''
echo 'Flash commands:'
echo "  fastboot flash boot_a $WIN_OUTPUT_DIR/boot-observable.img"
if [ -f "$ROOTFS_SPARSE_IMG" ]; then
    echo "  fastboot flash userdata $WIN_OUTPUT_DIR/rootfs-sparse.img"
else
    echo '  WARNING: rootfs-sparse.img not found; flash userdata manually after running scripts/03-build-rootfs.sh'
fi
echo "  fastboot --disable-verity --disable-verification flash vbmeta $WIN_OUTPUT_DIR/vbmeta_disabled.img"
echo '  fastboot reboot'