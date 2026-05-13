#!/bin/bash
set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
OUTPUT_DIR="$WORKDIR/output/debug"
WIN_OUTPUT_DIR="/mnt/c/repo/razorphone2linux/output/debug"
MKBOOTIMG="$WORKDIR/mkbootimg-tool/mkbootimg.py"
INIT_TEMPLATE="/mnt/c/repo/razorphone2linux/initramfs/init-debug.sh"
LOCAL_BUSYBOX_DEB="/mnt/c/repo/razorphone2linux/busybox-static_1%3a1.36.1-6ubuntu3.1_arm64.deb"
BOOT_IMG="$OUTPUT_DIR/boot-debug.img"
RAMDISK="$OUTPUT_DIR/initramfs-debug.cpio.gz"
VBMETA="$OUTPUT_DIR/vbmeta_disabled.img"

echo '=== Creating debug boot image for Razer Phone 2 ==='

if [ ! -f "$OUTPUT_DIR/Image.gz-dtb" ]; then
    echo "ERROR: Debug kernel image not found at $OUTPUT_DIR/Image.gz-dtb"
    echo "Run scripts/02-build-debug-kernel.sh first."
    exit 1
fi

if [ ! -f "$INIT_TEMPLATE" ]; then
    echo "ERROR: init template not found at $INIT_TEMPLATE"
    exit 1
fi

extract_arm64_busybox() {
    local pkg_dir extract_dir deb_path busybox_path apt_root apt_lists apt_cache apt_sources

    pkg_dir=$(mktemp -d)
    extract_dir=$(mktemp -d)
    apt_root=''
    apt_lists=''
    apt_cache=''
    apt_sources=''

    if [ -f "$LOCAL_BUSYBOX_DEB" ]; then
        echo '  Using local arm64 busybox deb from workspace...'
        cp "$LOCAL_BUSYBOX_DEB" "$pkg_dir/"
    fi

    deb_path=$(find "$pkg_dir" -maxdepth 1 -name 'busybox-static_*_arm64.deb' | head -n 1)
    if [ -z "$deb_path" ]; then
        apt_root=$(mktemp -d)
        apt_lists="$apt_root/lists"
        apt_cache="$apt_root/cache"
        apt_sources="$apt_root/sources.list"
        mkdir -p "$apt_lists/partial" "$apt_cache/archives/partial"

        cat > "$apt_sources" << 'EOF'
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-backports main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse
EOF

        echo '  Downloading busybox-static:arm64 from ubuntu-ports...'

        sudo apt-get \
            -o Dir::Etc::sourcelist="$apt_sources" \
            -o Dir::Etc::sourceparts="-" \
            -o Dir::State::lists="$apt_lists" \
            -o Dir::Cache::archives="$apt_cache/archives" \
            -o APT::Architecture=arm64 \
            update -qq

        sudo apt-get \
            -o Dir::Etc::sourcelist="$apt_sources" \
            -o Dir::Etc::sourceparts="-" \
            -o Dir::State::lists="$apt_lists" \
            -o Dir::Cache::archives="$apt_cache/archives" \
            -o APT::Architecture=arm64 \
            download busybox-static:arm64 >/dev/null

        find "$apt_cache/archives" -maxdepth 1 -name 'busybox-static_*_arm64.deb' -exec cp {} "$pkg_dir/" \;
        deb_path=$(find "$pkg_dir" -maxdepth 1 -name 'busybox-static_*_arm64.deb' | head -n 1)
    fi

    if [ -z "$deb_path" ]; then
        echo 'ERROR: failed to download busybox-static:arm64'
        rm -rf "$pkg_dir" "$extract_dir" "$apt_root"
        return 1
    fi

    dpkg-deb -x "$deb_path" "$extract_dir"
    busybox_path=$(find "$extract_dir" -path '*/bin/busybox' | head -n 1)
    if [ -z "$busybox_path" ]; then
        echo 'ERROR: arm64 busybox binary not found in package'
        rm -rf "$pkg_dir" "$extract_dir" "$apt_root"
        return 1
    fi

    cp "$busybox_path" "$OUTPUT_DIR/busybox-aarch64"
    chmod +x "$OUTPUT_DIR/busybox-aarch64"
    rm -rf "$pkg_dir" "$extract_dir" "$apt_root"
}

echo '[1/4] Preparing arm64 busybox...'
mkdir -p "$OUTPUT_DIR"
mkdir -p "$WIN_OUTPUT_DIR"

if [ -f "$OUTPUT_DIR/busybox-aarch64" ] && ! file "$OUTPUT_DIR/busybox-aarch64" | grep -q 'ARM aarch64'; then
    echo '  Existing busybox-aarch64 is not arm64, replacing it...'
    rm -f "$OUTPUT_DIR/busybox-aarch64"
fi

if [ ! -f "$OUTPUT_DIR/busybox-aarch64" ]; then
    extract_arm64_busybox
fi

echo '[2/4] Building debug initramfs...'
INITRD_DIR=$(mktemp -d)
mkdir -p "$INITRD_DIR"/{bin,dev,etc,proc,run,sbin,sys,sysroot,tmp,usr/bin,usr/sbin}
cp "$OUTPUT_DIR/busybox-aarch64" "$INITRD_DIR/bin/busybox"
chmod +x "$INITRD_DIR/bin/busybox"
cp "$INIT_TEMPLATE" "$INITRD_DIR/init"
chmod +x "$INITRD_DIR/init"

for applet in sh mount umount switch_root sleep ls cat echo dmesg grep cut mkdir mknod ln readlink uname basename tr rm; do
    ln -sf busybox "$INITRD_DIR/bin/$applet"
done

(cd "$INITRD_DIR" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9) > "$RAMDISK"
rm -rf "$INITRD_DIR"

echo '[3/4] Creating debug boot image...'
CMDLINE='console=tty0 console=ttyMSM0,115200n8 console=ttyGS0,115200n8 earlycon=msm_geni_serial,0xA84000 keep_bootcon no_console_suspend initcall_debug clk_ignore_unused pd_ignore_unused fw_devlink=permissive root=/dev/disk/by-partlabel/userdata rootfstype=ext4 rootwait rw loglevel=8 ignore_loglevel printk.devkmsg=on panic=-1 debug_stay_initramfs=1'

python3 "$MKBOOTIMG" \
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

echo '[4/4] Creating disabled-verification vbmeta...'
python3 << 'PYEOF'
import os
import struct

outdir = os.path.expanduser('~/razorphone2linux/output/debug')
data = bytearray(4096)
data[0:4] = b'AVB0'
struct.pack_into('>I', data, 4, 1)
struct.pack_into('>I', data, 8, 1)
struct.pack_into('>I', data, 120, 3)

with open(os.path.join(outdir, 'vbmeta_disabled.img'), 'wb') as handle:
    handle.write(data)
PYEOF

cp -v "$BOOT_IMG" "$WIN_OUTPUT_DIR/boot-debug.img"
cp -v "$RAMDISK" "$WIN_OUTPUT_DIR/initramfs-debug.cpio.gz"
cp -v "$VBMETA" "$WIN_OUTPUT_DIR/vbmeta_disabled.img"
cp -v "$OUTPUT_DIR/busybox-aarch64" "$WIN_OUTPUT_DIR/busybox-aarch64"

echo ''
echo '=== DEBUG BOOT IMAGE COMPLETE ==='
ls -lh "$BOOT_IMG" "$RAMDISK" "$VBMETA"
echo ''
echo 'Flash commands:'
echo "  fastboot flash vbmeta_a $VBMETA"
echo "  fastboot flash boot_a $BOOT_IMG"
echo '  fastboot reboot'
