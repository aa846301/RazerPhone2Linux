#!/bin/bash
set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
KERNEL_DIR="$WORKDIR/kernel/linux"
OUTPUT_DIR="$WORKDIR/output"
NPROC=$(nproc)

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

echo '=== Step 1: Clean config and start fresh ==='
cd "$KERNEL_DIR"
make mrproper

echo '=== Step 2: Copy DTS and panel driver ==='
cp -v /mnt/c/repo/razorphone2linux/dts/sdm845-razer-aura.dts arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts
sed -i 's/\r$//' arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts

cp -v /mnt/c/repo/razorphone2linux/panel-driver/panel-novatek-nt36830.c drivers/gpu/drm/panel/panel-novatek-nt36830.c
sed -i 's/\r$//' drivers/gpu/drm/panel/panel-novatek-nt36830.c

echo '=== Step 3: Patch DTS Makefile ==='
if ! grep -q 'sdm845-razer-aura' arch/arm64/boot/dts/qcom/Makefile; then
    LAST_SDM845_LINE=$(grep -n 'sdm845-' arch/arm64/boot/dts/qcom/Makefile | tail -1 | cut -d: -f1)
    sed -i "${LAST_SDM845_LINE}a\\dtb-\$(CONFIG_ARCH_QCOM) += sdm845-razer-aura.dtb" arch/arm64/boot/dts/qcom/Makefile
    echo 'DTS Makefile patched'
else
    echo 'DTS Makefile already patched'
fi

echo '=== Step 4: Patch panel Kconfig ==='
if ! grep -q 'DRM_PANEL_NOVATEK_NT36830' drivers/gpu/drm/panel/Kconfig; then
    cat >> drivers/gpu/drm/panel/Kconfig << 'KCEOF'

config DRM_PANEL_NOVATEK_NT36830
	tristate "NovaTeK NT36830 Dual-DSI AMOLED panel with DSC"
	depends on OF
	depends on DRM_MIPI_DSI
	depends on BACKLIGHT_CLASS_DEVICE
	select DRM_DISPLAY_HELPER
	select DRM_DISPLAY_DSC_HELPER
	help
	  Say Y or M here if you want to enable support for the NovaTeK
	  NT36830 AMOLED display panel used in the Razer Phone 2.
KCEOF
    echo 'Panel Kconfig patched'
else
    echo 'Panel Kconfig already patched'
fi

echo '=== Step 5: Patch panel Makefile ==='
if ! grep -q 'panel-novatek-nt36830' drivers/gpu/drm/panel/Makefile; then
    echo 'obj-$(CONFIG_DRM_PANEL_NOVATEK_NT36830) += panel-novatek-nt36830.o' >> drivers/gpu/drm/panel/Makefile
    echo 'Panel Makefile patched'
else
    echo 'Panel Makefile already patched'
fi

echo '=== Step 6: Configure kernel ==='
cat > /tmp/razer_aura.config << 'FRAGEOF'
# --- Display ---
# DRM_MSM: built as module so a panel init failure cannot prevent boot.
# simpledrm stays enabled as the boot-time fallback (bootloader framebuffer).
CONFIG_DRM_MSM=m
CONFIG_DRM_SIMPLEDRM=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_PANEL_NOVATEK_NT36830=m

# --- Touchscreen (Synaptics RMI4 on I2C-7) ---
CONFIG_RMI4_CORE=y
CONFIG_RMI4_I2C=y
CONFIG_RMI4_F01=y
CONFIG_RMI4_F12=y

# --- WiFi (Qualcomm WCN3990 / ath10k_snoc) ---
CONFIG_ATH10K=m
CONFIG_ATH10K_SNOC=m

# --- USB ---
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_ACM=y
CONFIG_USB_CONFIGFS_SERIAL=y
CONFIG_USB_CONFIGFS_ECM=y
CONFIG_USB_CONFIGFS_RNDIS=y
CONFIG_USB_G_SERIAL=m
CONFIG_USB_ETH=m
CONFIG_USB_ACM=y
CONFIG_USB_SERIAL=y
CONFIG_USB_SERIAL_GENERIC=y

# --- Crash capture ---
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_RAM=y

# --- Framebuffer / VT (fallback for simpledrm) ---
CONFIG_FB=y
CONFIG_FB_SIMPLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y

# --- Filesystems ---
CONFIG_EXT4_FS=y
CONFIG_TMPFS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
FRAGEOF

make defconfig
./scripts/kconfig/merge_config.sh -m .config arch/arm64/configs/sdm845.config
./scripts/kconfig/merge_config.sh -m .config /tmp/razer_aura.config
make olddefconfig

echo '--- Verifying critical configs ---'
for cfg in ARCH_QCOM DRM_MSM DRM_SIMPLEDRM DRM_PANEL_NOVATEK_NT36830 RMI4_I2C ATH10K_SNOC USB_DWC3 USB_CONFIGFS_ECM DRM_DISPLAY_DSC_HELPER PSTORE_RAM; do
    val=$(grep "CONFIG_${cfg}[=]" .config || echo "  NOT FOUND")
    echo "  ${cfg}: ${val}"
done

echo '=== Step 7: Build kernel + DTBs + modules ==='
mkdir -p "$OUTPUT_DIR"
make -j"$NPROC" Image.gz dtbs modules 2>&1 | tee "$OUTPUT_DIR/build.log"

echo '=== Step 8: Collect build outputs ==='
make INSTALL_MOD_PATH="$OUTPUT_DIR/modules_install" modules_install
cp -v arch/arm64/boot/Image.gz "$OUTPUT_DIR/Image.gz"
cp -v arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb "$OUTPUT_DIR/sdm845-razer-aura.dtb"
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb > "$OUTPUT_DIR/Image.gz-dtb"

echo ''
echo '=== KERNEL BUILD COMPLETE ==='
du -h "$OUTPUT_DIR/Image.gz"
du -h "$OUTPUT_DIR/sdm845-razer-aura.dtb"
du -h "$OUTPUT_DIR/Image.gz-dtb"
ls -la "$OUTPUT_DIR/modules_install/lib/modules/"
