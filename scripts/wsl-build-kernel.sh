#!/bin/bash
set -euo pipefail

KDIR=~/razorphone2linux/kernel/linux
OUTPUT=~/razorphone2linux/output

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

NPROC=$(nproc)

echo "========================================"
echo " Kernel Build - Razer Phone 2"
echo " Parallel jobs: $NPROC"
echo "========================================"

cd "$KDIR"
mkdir -p "$OUTPUT"

# Step 1: Start with sdm845 defconfig or defconfig
echo "[1/4] Configuring kernel..."
if [ -f "arch/arm64/configs/sdm845_defconfig" ]; then
    make sdm845_defconfig
else
    make defconfig
fi

# Step 2: Apply Razer Phone 2 config fragment
echo "[2/4] Applying config fragment..."
cat > /tmp/razer_aura.config << 'CFGEOF'
CONFIG_ARCH_QCOM=y
CONFIG_DRM=y
CONFIG_DRM_MSM=y
CONFIG_DRM_PANEL_NOVATEK_NT36830=y
CONFIG_DRM_DISPLAY_HELPER=y
CONFIG_DRM_DISPLAY_DSC_HELPER=y
CONFIG_BACKLIGHT_CLASS_DEVICE=y
CONFIG_INPUT_TOUCHSCREEN=y
CONFIG_RMI4_CORE=y
CONFIG_RMI4_I2C=y
CONFIG_RMI4_F01=y
CONFIG_RMI4_F12=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_ATH10K=y
CONFIG_ATH10K_SNOC=y
CONFIG_BT=y
CONFIG_BT_HCIUART=y
CONFIG_BT_HCIUART_QCA=y
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
CONFIG_PHY_QCOM_QMP=y
CONFIG_PHY_QCOM_QUSB2=y
CONFIG_PHY_QCOM_QMP_USB=y
CONFIG_SCSI=y
CONFIG_SCSI_UFSHCD=y
CONFIG_SCSI_UFSHCD_PLATFORM=y
CONFIG_SCSI_UFS_QCOM=y
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
CONFIG_I2C=y
CONFIG_I2C_QCOM_GENI=y
CONFIG_SPI=y
CONFIG_SPI_QCOM_GENI=y
CONFIG_SERIAL_MSM=y
CONFIG_SERIAL_MSM_CONSOLE=y
CONFIG_REGULATOR=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_NET=y
CONFIG_INET=y
CONFIG_WIRELESS=y
CONFIG_RFKILL=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_RAM=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FB=y
CONFIG_REMOTEPROC=y
CONFIG_QCOM_Q6V5_MSS=y
CONFIG_QCOM_Q6V5_ADSP=y
CONFIG_QCOM_Q6V5_PAS=y
CONFIG_QCOM_SYSMON=y
CONFIG_RPMSG_QCOM_GLINK_SMEM=y
CONFIG_QCOM_PIL_INFO=y
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_SOC=y
CONFIG_SND_SOC_QCOM=y
CONFIG_SPMI=y
CONFIG_PINCTRL_QCOM_SPMI_PMIC=y
CONFIG_LEDS_CLASS=y
CFGEOF

./scripts/kconfig/merge_config.sh -m .config /tmp/razer_aura.config
make olddefconfig

# Force DRM_DISPLAY_HELPER=y (needed for built-in panel driver using DSC)
sed -i 's/CONFIG_DRM_DISPLAY_HELPER=m/CONFIG_DRM_DISPLAY_HELPER=y/' .config
make olddefconfig

echo "[3/4] Building kernel, DTBs, and modules..."
make -j"$NPROC" Image.gz dtbs modules 2>&1 | tee "$OUTPUT/build.log"

echo "[4/4] Collecting outputs..."
make INSTALL_MOD_PATH="$OUTPUT/modules_install" modules_install

cp -v arch/arm64/boot/Image.gz "$OUTPUT/Image.gz"
cp -v arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb "$OUTPUT/sdm845-razer-aura.dtb"
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb > "$OUTPUT/Image.gz-dtb"

echo ""
echo "========================================"
echo " Kernel build complete!"
echo "========================================"
ls -lh "$OUTPUT"/Image.gz "$OUTPUT"/sdm845-razer-aura.dtb "$OUTPUT"/Image.gz-dtb
echo "===BUILD_DONE==="
