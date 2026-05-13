#!/bin/bash
# ==========================================================================
# Razer Phone 2 (aura) - Kernel Build Script
# ==========================================================================
# Cross-compiles the mainline Linux kernel with Razer Phone 2 device tree
# and NT36830 panel driver.
#
# Usage: bash 02-build-kernel.sh [menuconfig]
#   Optional arg "menuconfig" opens kernel config editor before building.
#
# Prerequisites: Run 01-setup-environment.sh first.
# ==========================================================================

set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
KERNEL_DIR="$WORKDIR/kernel/linux"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$WORKDIR/output"

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

MAX_JOBS=4
NPROC=$(nproc)
if [ "$NPROC" -gt "$MAX_JOBS" ]; then
    BUILD_JOBS="$MAX_JOBS"
else
    BUILD_JOBS="$NPROC"
fi

echo "========================================"
echo " Razer Phone 2 - Kernel Build"
echo "========================================"
echo "Kernel dir: $KERNEL_DIR"
echo "Parallel jobs: $BUILD_JOBS"
echo ""

# -------------------------------------------------------
# Step 1: Install device tree and panel driver into kernel tree
# -------------------------------------------------------
echo "[1/6] Installing device tree and panel driver..."

# Copy DTS
cp -v "$PROJECT_DIR/dts/sdm845-razer-aura.dts" \
    "$KERNEL_DIR/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts"

# Copy panel driver
cp -v "$PROJECT_DIR/panel-driver/panel-novatek-nt36830.c" \
    "$KERNEL_DIR/drivers/gpu/drm/panel/panel-novatek-nt36830.c"

# -------------------------------------------------------
# Step 2: Patch DTS Makefile to include our device tree
# -------------------------------------------------------
echo "[2/6] Patching DTS Makefile..."
DTS_MAKEFILE="$KERNEL_DIR/arch/arm64/boot/dts/qcom/Makefile"

if ! grep -q "sdm845-razer-aura" "$DTS_MAKEFILE"; then
    # Find the line with the last sdm845 entry and add our DTB after it
    # Use sed to add after the last sdm845 dtb line
    LAST_SDM845_LINE=$(grep -n "sdm845-" "$DTS_MAKEFILE" | tail -1 | cut -d: -f1)
    if [ -n "$LAST_SDM845_LINE" ]; then
        sed -i "${LAST_SDM845_LINE}a\\dtb-\$(CONFIG_ARCH_QCOM) += sdm845-razer-aura.dtb" "$DTS_MAKEFILE"
        echo "  Added sdm845-razer-aura.dtb to DTS Makefile (after line $LAST_SDM845_LINE)"
    else
        # Fallback: append to end
        echo "dtb-\$(CONFIG_ARCH_QCOM) += sdm845-razer-aura.dtb" >> "$DTS_MAKEFILE"
        echo "  Added sdm845-razer-aura.dtb to DTS Makefile (appended)"
    fi
else
    echo "  sdm845-razer-aura.dtb already in DTS Makefile."
fi

# -------------------------------------------------------
# Step 3: Patch panel driver Kconfig and Makefile
# -------------------------------------------------------
echo "[3/6] Patching panel driver Kconfig and Makefile..."

PANEL_KCONFIG="$KERNEL_DIR/drivers/gpu/drm/panel/Kconfig"
PANEL_MAKEFILE="$KERNEL_DIR/drivers/gpu/drm/panel/Makefile"

# Add Kconfig entry if not present
if ! grep -q "DRM_PANEL_NOVATEK_NT36830" "$PANEL_KCONFIG"; then
    # Find the NT36523 entry and add our entry after it
    cat >> "$PANEL_KCONFIG" << 'KCONFIG_EOF'

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
	  This panel uses Dual DSI with Display Stream Compression (DSC)
	  at 1440x2560 resolution.

	  If unsure, say N.
KCONFIG_EOF
    echo "  Added DRM_PANEL_NOVATEK_NT36830 to Kconfig"
else
    echo "  DRM_PANEL_NOVATEK_NT36830 already in Kconfig."
fi

# Add Makefile entry if not present
if ! grep -q "panel-novatek-nt36830" "$PANEL_MAKEFILE"; then
    echo "obj-\$(CONFIG_DRM_PANEL_NOVATEK_NT36830) += panel-novatek-nt36830.o" >> "$PANEL_MAKEFILE"
    echo "  Added panel-novatek-nt36830 to panel Makefile"
else
    echo "  panel-novatek-nt36830 already in panel Makefile."
fi

# -------------------------------------------------------
# Step 4: Configure kernel
# -------------------------------------------------------
echo "[4/6] Configuring kernel..."
cd "$KERNEL_DIR"

# Start with sdm845 defconfig (from the sdm845-mainline project)
if [ -f "arch/arm64/configs/sdm845_defconfig" ]; then
    make sdm845_defconfig
elif [ -f "arch/arm64/configs/defconfig" ]; then
    make defconfig
else
    echo "ERROR: No suitable defconfig found!"
    exit 1
fi

# Apply additional config options for Razer Phone 2
echo "Applying Razer Phone 2 config fragment..."
cat > /tmp/razer_aura_fragment.config << 'CONFIG_EOF'
# ============================================================
# Razer Phone 2 (aura) kernel config fragment
# ============================================================

# Platform
CONFIG_ARCH_QCOM=y

# Display (simpledrm first; full MSM/NT36830 can load after userspace)
CONFIG_DRM=y
CONFIG_DRM_MSM=m
CONFIG_DRM_PANEL_NOVATEK_NT36830=m
CONFIG_DRM_DISPLAY_HELPER=y
CONFIG_DRM_DISPLAY_DSC_HELPER=y
CONFIG_BACKLIGHT_CLASS_DEVICE=y

# Touchscreen (Synaptics RMI4)
CONFIG_INPUT_TOUCHSCREEN=y
CONFIG_RMI4_CORE=y
CONFIG_RMI4_I2C=y
CONFIG_RMI4_F01=y
CONFIG_RMI4_F12=y

# WiFi (WCN3990 via ath10k)
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_ATH10K=y
CONFIG_ATH10K_SNOC=y
CONFIG_ATH10K_DEBUG=n

# Bluetooth (WCN3990)
CONFIG_BT=y
CONFIG_BT_HCIUART=y
CONFIG_BT_HCIUART_QCA=y

# USB (DWC3 + Gadget for serial debug + Host for Klipper MCU)
CONFIG_USB=y
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_ACM=y
CONFIG_USB_CONFIGFS_SERIAL=y
CONFIG_USB_G_SERIAL=m
CONFIG_USB_ACM=y
CONFIG_USB_SERIAL=y
CONFIG_USB_SERIAL_GENERIC=y

# USB PHY
CONFIG_PHY_QCOM_QMP=y
CONFIG_PHY_QCOM_QUSB2=y
CONFIG_PHY_QCOM_QMP_USB=y

# Storage (UFS)
CONFIG_SCSI=y
CONFIG_SCSI_UFSHCD=y
CONFIG_SCSI_UFSHCD_PLATFORM=y
CONFIG_SCSI_UFS_QCOM=y
CONFIG_PHY_QCOM_UFS=y

# Qualcomm platform support
CONFIG_QCOM_RPMH=y
CONFIG_QCOM_RPMHPD=y
CONFIG_QCOM_SCM=y
CONFIG_QCOM_SMEM=y
CONFIG_QCOM_SOCINFO=y
CONFIG_QCOM_PDC=y
CONFIG_QCOM_LLCC=y
CONFIG_QCOM_SDM845_LLCC=y
CONFIG_PINCTRL_SDM845=y
CONFIG_REGULATOR_QCOM_RPMH=y
CONFIG_INTERCONNECT_QCOM=y
CONFIG_INTERCONNECT_QCOM_SDM845=y

# I2C/SPI (QUP)
CONFIG_I2C=y
CONFIG_I2C_QCOM_GENI=y
CONFIG_SPI=y
CONFIG_SPI_QCOM_GENI=y

# Serial console (debug UART)
CONFIG_SERIAL_MSM=y
CONFIG_SERIAL_MSM_CONSOLE=y

# Power management
CONFIG_REGULATOR=y
CONFIG_REGULATOR_QCOM_SPMI=y

# Filesystem (for rootfs)
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y

# Basic networking (for WiFi/SSH)
CONFIG_NET=y
CONFIG_INET=y
CONFIG_WIRELESS=y
CONFIG_RFKILL=y

# Kernel modules
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y

# Essential system
CONFIG_PRINTK=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_CGROUPS=y
CONFIG_INOTIFY_USER=y
CONFIG_SIGNALFD=y
CONFIG_TIMERFD=y
CONFIG_EPOLL=y

# Ramoops for crash debugging
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_RAM=y

# Simple framebuffer (early boot display)
CONFIG_DRM_SIMPLEDRM=y
CONFIG_SYSFB_SIMPLEFB=y
CONFIG_OF_EARLY_FLATTREE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FB=y

# Remoteproc (for modem, wifi, adsp, etc.)
CONFIG_REMOTEPROC=y
CONFIG_QCOM_Q6V5_MSS=y
CONFIG_QCOM_Q6V5_ADSP=y
CONFIG_QCOM_Q6V5_WCSS=y
CONFIG_QCOM_Q6V5_PAS=y
CONFIG_QCOM_SYSMON=y
CONFIG_QCOM_AOSS_QMP=y
CONFIG_RPMSG=y
CONFIG_RPMSG_QCOM_SMD=y
CONFIG_RPMSG_QCOM_GLINK=y
CONFIG_RPMSG_QCOM_GLINK_SMEM=y
CONFIG_QRTR=y
CONFIG_MHI_BUS=y
CONFIG_QCOM_PIL_INFO=y
CONFIG_QCOM_WCNSS_PIL=y

# IPA (modem data)
CONFIG_QCOM_IPA=y

# Audio (optional, for completeness)
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_SOC=y
CONFIG_SND_SOC_QCOM=y
CONFIG_SND_SOC_SDM845=y

# PMIC
CONFIG_MFD_QCOM_RPM=y
CONFIG_SPMI=y
CONFIG_PINCTRL_QCOM_SPMI_PMIC=y

# Charger (PMI8998)
CONFIG_CHARGER_QCOM_SMBB=y

# LED (PMI8998 flash)
CONFIG_LEDS_CLASS=y
CONFIG_LEDS_CLASS_FLASH=y
CONFIG_LEDS_QCOM_FLASH=y
CONFIG_LEDS_QCOM_LPG=y
CONFIG_LEDS_PWM=y
CONFIG_BACKLIGHT_PWM=y
CONFIG_PWM=y
CONFIG_PWM_QCOM_LPG=y
CONFIG_DRM_PANEL_BACKLIGHT_QUIRKS=y
CONFIG_OF_EARLY_FLATTREE=y
CONFIG_EOF

# Merge the fragment into the current config
./scripts/kconfig/merge_config.sh .config /tmp/razer_aura_fragment.config

# Keep the Qualcomm Wi-Fi bring-up chain consistently modular so userspace can
# load it after rootfs is available and we can validate the .ko artifacts.
./scripts/config --module CFG80211
./scripts/config --module MAC80211
./scripts/config --module ATH10K
./scripts/config --module ATH10K_SNOC
./scripts/config --module QCOM_Q6V5_WCSS
./scripts/config --module QCOM_WCNSS_PIL
./scripts/config --module QCOM_RPROC_COMMON
./scripts/config --module RPMSG_QCOM_SMD
./scripts/config --module RPMSG_QCOM_GLINK
./scripts/config --module RPMSG_QCOM_GLINK_SMEM
./scripts/config --module QCOM_SYSMON
./scripts/config --enable QCOM_AOSS_QMP
./scripts/config --module QRTR
./scripts/config --module MHI_BUS

# Optional: open menuconfig for manual adjustments
if [ "${1:-}" = "menuconfig" ]; then
    make menuconfig
fi

# Finalize config
make olddefconfig

echo "[4/6] Kernel configured."

# -------------------------------------------------------
# Step 5: Build kernel, DTBs, and modules
# -------------------------------------------------------
echo "[5/6] Building kernel (this will take a while)..."
if ! make -j"$BUILD_JOBS" Image.gz dtbs modules 2>&1 | tee "$OUTPUT_DIR/build.log"; then
    echo '' | tee -a "$OUTPUT_DIR/build.log"
    echo 'Parallel build failed under WSL, retrying with -j1 for a stable artifact...' | tee -a "$OUTPUT_DIR/build.log"
    make olddefconfig 2>&1 | tee -a "$OUTPUT_DIR/build.log"
    make prepare modules_prepare 2>&1 | tee -a "$OUTPUT_DIR/build.log"
    make -j1 Image.gz dtbs modules 2>&1 | tee -a "$OUTPUT_DIR/build.log"
fi

echo "[5/6] Build complete."

# -------------------------------------------------------
# Step 6: Install modules and collect outputs
# -------------------------------------------------------
echo "[6/6] Collecting build outputs..."

# Install modules to output directory
rm -rf "$OUTPUT_DIR/modules_install"
make INSTALL_MOD_PATH="$OUTPUT_DIR/modules_install" modules_install

KERNEL_RELEASE=$(make -s kernelrelease)
for module_path in \
    "kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko" \
    "kernel/drivers/net/wireless/ath/ath10k/ath10k_snoc.ko" \
    "kernel/drivers/remoteproc/qcom_q6v5_wcss.ko" \
    "kernel/drivers/remoteproc/qcom_wcnss_pil.ko"; do
    if [ ! -f "$OUTPUT_DIR/modules_install/lib/modules/$KERNEL_RELEASE/$module_path" ]; then
        echo "ERROR: expected Wi-Fi module missing after modules_install: $module_path"
        exit 1
    fi
done

# Copy kernel image
cp -v arch/arm64/boot/Image.gz "$OUTPUT_DIR/Image.gz"

# Copy DTB
cp -v arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb "$OUTPUT_DIR/sdm845-razer-aura.dtb"

# Create concatenated Image.gz-dtb (needed for some bootloaders)
cat arch/arm64/boot/Image.gz \
    arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb \
    > "$OUTPUT_DIR/Image.gz-dtb"

echo ""
echo "========================================"
echo " Kernel build complete!"
echo "========================================"
echo ""
echo "Outputs in: $OUTPUT_DIR"
echo "  Image.gz            - Compressed kernel image"
echo "  sdm845-razer-aura.dtb - Device tree blob"
echo "  Image.gz-dtb        - Combined kernel + DTB"
echo "  modules_install/    - Kernel modules"
echo "  build.log           - Build log"
echo ""
echo "Next: Run bash 03-build-rootfs.sh"
