#!/bin/bash
# ==========================================================================
# Razer Phone 2 (aura) - Boot Image Creator
# ==========================================================================
# Creates an Android-compatible boot.img for the Razer Phone 2 using
# the compiled mainline Linux kernel and device tree blob.
#
# Usage:
#   bash 04-make-boot-image.sh
#   RAZER_BOOT_DISPLAY_MODE=console bash 04-make-boot-image.sh
#
# Prerequisites:
#   - Run 02-build-kernel.sh first (kernel + DTB needed)
#   - Run 03-build-rootfs.sh first (rootfs sparse image needed)
# ==========================================================================

set -euo pipefail

WORKDIR="${RAZER_WORKDIR:-$HOME/razorphone2linux}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/config/build.env"
IMAGE_PROFILE="${RAZER_IMAGE_PROFILE:-printer}"
case "$IMAGE_PROFILE" in
    base|printer) ;;
    *) echo "ERROR: RAZER_IMAGE_PROFILE must be base or printer."; exit 2 ;;
esac
OUTPUT_DIR="$WORKDIR/output/$IMAGE_PROFILE"
BOOT_IMG="$OUTPUT_DIR/boot.img"
WIN_OUTPUT_DIR="$PROJECT_DIR/output/$IMAGE_PROFILE"
LOCAL_MKBOOTIMG="$WORKDIR/mkbootimg-tool/mkbootimg.py"
KERNEL_RELEASE_FILE="$OUTPUT_DIR/kernel.release"
ROOTFS_RELEASE_FILE="$OUTPUT_DIR/rootfs.kernel-release"
KERNEL_FLAVOR_FILE="$OUTPUT_DIR/kernel.flavor"
DISPLAY_MODE="${RAZER_BOOT_DISPLAY_MODE:-helix}"

mkdir -p "$OUTPUT_DIR" "$WIN_OUTPUT_DIR"

case "$DISPLAY_MODE" in
    helix|console) ;;
    *)
        echo "ERROR: RAZER_BOOT_DISPLAY_MODE must be 'helix' or 'console'."
        exit 2
        ;;
esac

echo "========================================"
echo " Razer Phone 2 - Boot Image Creator"
echo "========================================"
echo "Display mode: $DISPLAY_MODE"
echo "Image profile: $IMAGE_PROFILE"

if [ -f "$LOCAL_MKBOOTIMG" ]; then
    MKBOOTIMG_CMD=(python3 "$LOCAL_MKBOOTIMG")
elif command -v mkbootimg &>/dev/null; then
    MKBOOTIMG_CMD=(mkbootimg)
else
    echo "ERROR: mkbootimg tool not found. Expected $LOCAL_MKBOOTIMG or mkbootimg in PATH."
    exit 1
fi

# -------------------------------------------------------
# Verify prerequisites
# -------------------------------------------------------
if [ ! -f "$OUTPUT_DIR/Image.gz" ]; then
    echo "ERROR: Kernel image not found at $OUTPUT_DIR/Image.gz"
    echo "Please run 02-build-kernel.sh first."
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/sdm845-razer-aura.dtb" ]; then
    echo "ERROR: Device tree blob not found at $OUTPUT_DIR/sdm845-razer-aura.dtb"
    echo "Please run 02-build-kernel.sh first."
    exit 1
fi

if [ ! -f "$KERNEL_RELEASE_FILE" ]; then
    echo "ERROR: $KERNEL_RELEASE_FILE not found."
    echo "Run 02-build-kernel.sh first so boot/rootfs use the same kernel release."
    exit 1
fi

KERNEL_RELEASE=$(tr -d '\r\n' < "$KERNEL_RELEASE_FILE")
if [ ! -d "$OUTPUT_DIR/modules_install/lib/modules/$KERNEL_RELEASE" ]; then
    echo "ERROR: modules for kernel release '$KERNEL_RELEASE' are missing."
    echo "Expected: $OUTPUT_DIR/modules_install/lib/modules/$KERNEL_RELEASE"
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/rootfs-sparse.img" ] || [ ! -f "$ROOTFS_RELEASE_FILE" ]; then
    echo "ERROR: rootfs-sparse.img or rootfs.kernel-release is missing."
    echo "Run 03-build-rootfs.sh after 02-build-kernel.sh before packaging boot.img."
    exit 1
fi

ROOTFS_RELEASE=$(tr -d '\r\n' < "$ROOTFS_RELEASE_FILE")
if [ "$ROOTFS_RELEASE" != "$KERNEL_RELEASE" ]; then
    echo "ERROR: rootfs modules were built for '$ROOTFS_RELEASE' but boot kernel is '$KERNEL_RELEASE'."
    echo "Rebuild in order: 02-build-kernel.sh -> 03-build-rootfs.sh -> 04-make-boot-image.sh"
    exit 1
fi

# -------------------------------------------------------
# Step 1: Create combined Image.gz-dtb
# -------------------------------------------------------
echo "[1/4] Creating combined kernel + DTB image..."
cat "$OUTPUT_DIR/Image.gz" "$OUTPUT_DIR/sdm845-razer-aura.dtb" \
    > "$OUTPUT_DIR/Image.gz-dtb"
echo "  Created Image.gz-dtb ($(du -h "$OUTPUT_DIR/Image.gz-dtb" | cut -f1))"

# -------------------------------------------------------
# Step 2: Build custom busybox initramfs (bypasses klibc run-init bug)
# -------------------------------------------------------
echo "[2/4] Building custom initramfs..."

INIT_SCRIPT="$PROJECT_DIR/initramfs/init-boot.sh"
BUSYBOX_BIN="$OUTPUT_DIR/busybox-aarch64"
RAMDISK="$OUTPUT_DIR/initramfs-boot.cpio.gz"

if [ ! -f "$INIT_SCRIPT" ]; then
    echo "ERROR: $INIT_SCRIPT not found"
    exit 1
fi

# Find ARM64 busybox binary
if [ ! -f "$BUSYBOX_BIN" ] || ! file "$BUSYBOX_BIN" | grep -q 'ARM aarch64'; then
    BUSYBOX_BIN="$OUTPUT_DIR/debug/busybox-aarch64"
fi
if [ ! -f "$BUSYBOX_BIN" ] || ! file "$BUSYBOX_BIN" | grep -q 'ARM aarch64'; then
    echo "ERROR: ARM64 busybox not found at output/busybox-aarch64"
    exit 1
fi
echo "  busybox: $BUSYBOX_BIN"

# UFS PHY module (only needed when PHY_QCOM_QMP_UFS=m). Pick the raw build
# tree that produced this boot image so contrast kernels do not inherit stale
# modules from the normal mainline tree.
KERNEL_FLAVOR=""
if [ -f "$KERNEL_FLAVOR_FILE" ]; then
    KERNEL_FLAVOR=$(tr -d '\r\n' < "$KERNEL_FLAVOR_FILE")
fi
case "$KERNEL_FLAVOR" in
    pmos-sdm845-contrast)
        UFS_PHY_KO="$WORKDIR/kernel/pmos-sdm845/drivers/phy/qualcomm/phy-qcom-qmp-ufs.ko"
        ;;
    *)
        UFS_PHY_KO="$WORKDIR/kernel/linux/drivers/phy/qualcomm/phy-qcom-qmp-ufs.ko"
        ;;
esac
if [ -f "$UFS_PHY_KO" ]; then
    echo "  UFS PHY module: $UFS_PHY_KO ($(du -h "$UFS_PHY_KO" | cut -f1))"
else
    echo "  UFS PHY module not present; assuming it is built into the kernel."
fi

INITRD_DIR=$(mktemp -d)
mkdir -p "$INITRD_DIR"/{bin,dev,run,proc,sys,sysroot}
mkdir -p "$INITRD_DIR/sys/kernel/config"
mkdir -p "$INITRD_DIR/dev/pts"
mkdir -p "$INITRD_DIR/lib/modules"

# Install busybox and applet symlinks
cp "$BUSYBOX_BIN" "$INITRD_DIR/bin/busybox"
chmod +x "$INITRD_DIR/bin/busybox"
for cmd in sh ash cat echo ls mkdir mknod mount umount sleep ln \
           find grep sed switch_root mdev blkid insmod; do
    ln -sf busybox "$INITRD_DIR/bin/$cmd"
done
ln -sf ../bin "$INITRD_DIR/sbin"

# Install UFS PHY module into initramfs when it is modular.
if [ -f "$UFS_PHY_KO" ]; then
    cp "$UFS_PHY_KO" "$INITRD_DIR/lib/modules/phy-qcom-qmp-ufs.ko"
fi

# Install init script
cp "$INIT_SCRIPT" "$INITRD_DIR/init"
chmod +x "$INITRD_DIR/init"

# Create /dev/console node (needed before devtmpfs mount)
mknod "$INITRD_DIR/dev/console" c 5 1 2>/dev/null || true

(cd "$INITRD_DIR" && find . | cpio -o -H newc 2>/dev/null | gzip -9) > "$RAMDISK"
rm -rf "$INITRD_DIR"
echo "  Created initramfs-boot.cpio.gz ($(du -h "$RAMDISK" | cut -f1))"

# -------------------------------------------------------
# Step 3: Create boot.img
# -------------------------------------------------------
echo "[3/4] Creating boot.img..."

# Kernel command line for mainline Linux on Razer Phone 2.
# Keep the final ttyMSM0 console for the SDM845 display race workaround.
CMDLINE_COMMON="earlycon=msm_geni_serial,0xA84000 console=ttyMSM0,115200n8 console=ttyGS0,115200 clk_ignore_unused pd_ignore_unused fw_devlink=permissive root=/dev/disk/by-partlabel/userdata rootfstype=ext4 rootwait rw loglevel=7 pcie_aspm=off panic=30 init=/usr/lib/systemd/systemd"
case "$DISPLAY_MODE" in
    helix)
        CMDLINE="$CMDLINE_COMMON fbcon=map:99 vt.global_cursor_default=0 console=ttyMSM0,115200n8"
        ;;
    console)
        CMDLINE="$CMDLINE_COMMON console=tty0 vt.global_cursor_default=1 razer_fb_clear=0 console=ttyMSM0,115200n8"
        ;;
esac

if [ -n "${RAZER_EXTRA_CMDLINE:-}" ]; then
    CMDLINE="$CMDLINE $RAZER_EXTRA_CMDLINE"
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

echo "  Created boot.img ($(du -h "$BOOT_IMG" | cut -f1))"

# -------------------------------------------------------
# Step 4: Create disabled-verification vbmeta
# -------------------------------------------------------
echo "[4/4] Creating vbmeta with verification disabled..."

# Create a minimal vbmeta that disables AVB verification
# This allows booting unsigned images
python3 -c "
import struct

# AVB vbmeta header layout (see external/avb/libavb/avb_vbmeta_image.h):
#   Offset 0:    magic 'AVB0' (4 bytes)
#   Offset 4:    required_libavb_version_major (4 bytes, big-endian)
#   Offset 8:    required_libavb_version_minor (4 bytes, big-endian)
#   Offset 12:   authentication_data_block_size (8 bytes)
#   Offset 20:   auxiliary_data_block_size (8 bytes)
#   Offset 28:   algorithm_type (4 bytes) = 0 (none)
#   Offset 32-119: hash/signature offsets (zeroed = no auth)
#   Offset 120:  flags (4 bytes, big-endian)
#      bit 0 = AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED
#      bit 1 = AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED

data = bytearray(4096)
# Magic
data[0:4] = b'AVB0'
# Major version = 1
struct.pack_into('>I', data, 4, 1)
# Minor version = 1
struct.pack_into('>I', data, 8, 1)
# Flags = 3 (disable both hashtree and verification)
struct.pack_into('>I', data, 120, 3)

with open('$OUTPUT_DIR/vbmeta_disabled.img', 'wb') as f:
    f.write(bytes(data))
print('  Created vbmeta_disabled.img')
" 2>/dev/null || {
    # Fallback: create empty vbmeta with avbtool if available
    echo "  WARNING: Could not create vbmeta. Create manually or use stock vbmeta with --disable-verity."
}

mkdir -p "$WIN_OUTPUT_DIR"
cp -f "$BOOT_IMG" "$WIN_OUTPUT_DIR/boot.img"
cp -f "$RAMDISK" "$WIN_OUTPUT_DIR/$(basename "$RAMDISK")"
cp -f "$KERNEL_RELEASE_FILE" "$WIN_OUTPUT_DIR/kernel.release"
cp -f "$ROOTFS_RELEASE_FILE" "$WIN_OUTPUT_DIR/rootfs.kernel-release"
if [ -f "$OUTPUT_DIR/vbmeta_disabled.img" ]; then
    cp -f "$OUTPUT_DIR/vbmeta_disabled.img" "$WIN_OUTPUT_DIR/vbmeta_disabled.img"
fi

echo ""
echo "========================================"
echo " Boot image creation complete!"
echo "========================================"
echo ""
echo "Output files:"
echo "  $BOOT_IMG"
echo "  $OUTPUT_DIR/rootfs-sparse.img"
echo "  $OUTPUT_DIR/vbmeta_disabled.img"
echo ""
echo "========================================"
echo " FLASHING INSTRUCTIONS"
echo "========================================"
echo ""
echo "1. Enable Developer Options on Razer Phone 2"
echo "   Settings > About Phone > Tap Build Number 7 times"
echo ""
echo "2. Enable OEM Unlocking"
echo "   Settings > Developer Options > Enable OEM unlocking"
echo ""
echo "3. Reboot to bootloader"
echo "   adb reboot bootloader"
echo ""
echo "4. Unlock bootloader (WARNING: This will wipe all data!)"
echo "   fastboot oem unlock"
echo ""
echo "5. Flash boot image to both slots and flash rootfs"
echo '   fastboot flash boot_a output\boot.img && fastboot flash boot_b output\boot.img && fastboot flash userdata output\rootfs-sparse.img && fastboot reboot'
echo ""
echo "6. Disable verified boot (allows unsigned images, when required)"
echo "   fastboot --disable-verity --disable-verification flash vbmeta $OUTPUT_DIR/vbmeta_disabled.img"
echo ""
echo "7. First boot will be slow (resizing filesystem)."
echo "   Connect via USB serial (ttyGS0) or WiFi SSH for access."
echo ""
echo "Default credentials:  klipper / klipper"
echo "Change immediately after first boot!"
