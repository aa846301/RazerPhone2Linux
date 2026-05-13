#!/bin/bash
set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
KERNEL_DIR="$WORKDIR/kernel/linux"
OUTPUT_DIR="$WORKDIR/output/debug"
WIN_OUTPUT_DIR="/mnt/c/repo/razorphone2linux/output/debug"
MAX_JOBS=4
NPROC=$(nproc)
if [ "$NPROC" -gt "$MAX_JOBS" ]; then
    BUILD_JOBS="$MAX_JOBS"
else
    BUILD_JOBS="$NPROC"
fi

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

echo '=== Debug kernel build for Razer Phone 2 ==='

cd "$KERNEL_DIR"

echo '[1/6] Cleaning kernel tree...'
make mrproper

echo '[2/6] Syncing DTS and panel driver sources...'
bash /mnt/c/repo/razorphone2linux/scripts/patch-kernel-tree.sh

echo '[2.5/6] Verifying DTS matches debug-safe USB bring-up policy...'
DEBUG_DTS="$KERNEL_DIR/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts"
check_dts_contains() {
    local needle="$1"
    local label="$2"

    if ! grep -Fq "$needle" "$DEBUG_DTS"; then
        echo "ERROR: expected DTS setting missing: $label"
        echo "       needle: $needle"
        exit 1
    fi
}

check_dts_contains 'qcom,select-utmi-as-pipe-clk;' 'usb_1 uses UTMI pipe clock selection'
check_dts_contains 'dr_mode = "peripheral";' 'usb_1_dwc3 forces peripheral mode'
check_dts_contains 'maximum-speed = "high-speed";' 'usb_1_dwc3 forces USB2 high-speed'
check_dts_contains 'phys = <&usb_1_hsphy>;' 'usb_1_dwc3 only binds HS PHY'
check_dts_contains 'phy-names = "usb2-phy";' 'usb_1_dwc3 exposes only usb2-phy'
check_dts_contains '&usb_1_qmpphy {' 'usb_1_qmpphy node exists for verification'
check_dts_contains 'status = "disabled";' 'usb_1_qmpphy is disabled'

echo '[3/6] Writing debug config fragment...'
cat > /tmp/razer_aura_debug.config << 'EOF'
CONFIG_RMI4_CORE=y
CONFIG_RMI4_I2C=y
CONFIG_RMI4_F01=y
CONFIG_RMI4_F12=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_ATH10K=y
CONFIG_ATH10K_SNOC=y
CONFIG_USB=y
CONFIG_CONFIGFS_FS=y
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_USB_GADGET=y
CONFIG_USB_LIBCOMPOSITE=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_SERIAL=y
CONFIG_USB_CONFIGFS_ACM=y
CONFIG_USB_ACM=y
CONFIG_USB_SERIAL=y
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_USB_G_SERIAL=y
CONFIG_USB_F_ACM=y
CONFIG_USB_U_SERIAL=y
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_RAM=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_PRINTK=y
CONFIG_DYNAMIC_DEBUG=y
CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_SYSFB=y
CONFIG_SYSFB_SIMPLEFB=y
CONFIG_FB=y
CONFIG_FB_SIMPLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_DRM_FBDEV_EMULATION=y
# CONFIG_EFI is not set
# CONFIG_EFI_STUB is not set
# CONFIG_EFI_ARMSTUB is not set
# CONFIG_SYSFB_EFI is not set
# CONFIG_DRM_MSM is not set
# CONFIG_DRM_PANEL_NOVATEK_NT36830 is not set
EOF

echo '[4/6] Merging configs...'
make defconfig
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/sdm845.config
./scripts/kconfig/merge_config.sh -m .config /tmp/razer_aura_debug.config
make olddefconfig
make prepare modules_prepare

echo '--- Verifying debug-critical configs ---'
for cfg in \
    DRM_SIMPLEDRM \
    SYSFB_SIMPLEFB \
    USB_G_SERIAL \
    BLK_DEV_INITRD \
    RD_GZIP \
    PSTORE \
    SERIAL_MSM_CONSOLE; do
    grep "CONFIG_${cfg}[=]" .config || echo "  WARNING: ${cfg} NOT FOUND"
done

grep '^# CONFIG_DRM_MSM is not set' .config || echo '  WARNING: DRM_MSM still enabled'

echo '[5/6] Building Image.gz and DTBs...'
mkdir -p "$OUTPUT_DIR"
mkdir -p "$WIN_OUTPUT_DIR"

if ! make -j"$BUILD_JOBS" Image.gz dtbs 2>&1 | tee "$OUTPUT_DIR/build-debug.log"; then
    echo '' | tee -a "$OUTPUT_DIR/build-debug.log"
    echo 'Parallel build failed under WSL, retrying with -j1 for a stable debug artifact...' | tee -a "$OUTPUT_DIR/build-debug.log"
    make olddefconfig 2>&1 | tee -a "$OUTPUT_DIR/build-debug.log"
    make prepare modules_prepare 2>&1 | tee -a "$OUTPUT_DIR/build-debug.log"
    make -j1 Image.gz dtbs 2>&1 | tee -a "$OUTPUT_DIR/build-debug.log"
fi

echo '[6/6] Collecting debug build outputs...'
cp -v arch/arm64/boot/Image.gz "$OUTPUT_DIR/Image.gz"
cp -v arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb "$OUTPUT_DIR/sdm845-razer-aura.dtb"
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb > "$OUTPUT_DIR/Image.gz-dtb"
cp -v .config "$OUTPUT_DIR/kernel-debug.config"
cp -v "$OUTPUT_DIR/Image.gz" "$WIN_OUTPUT_DIR/Image.gz"
cp -v "$OUTPUT_DIR/sdm845-razer-aura.dtb" "$WIN_OUTPUT_DIR/sdm845-razer-aura.dtb"
cp -v "$OUTPUT_DIR/Image.gz-dtb" "$WIN_OUTPUT_DIR/Image.gz-dtb"
cp -v "$OUTPUT_DIR/kernel-debug.config" "$WIN_OUTPUT_DIR/kernel-debug.config"
cp -v "$OUTPUT_DIR/build-debug.log" "$WIN_OUTPUT_DIR/build-debug.log"

echo ''
echo '=== DEBUG KERNEL BUILD COMPLETE ==='
ls -lh "$OUTPUT_DIR/Image.gz" "$OUTPUT_DIR/sdm845-razer-aura.dtb" "$OUTPUT_DIR/Image.gz-dtb" "$OUTPUT_DIR/kernel-debug.config"
