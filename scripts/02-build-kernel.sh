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

WORKDIR="${RAZER_WORKDIR:-$HOME/razorphone2linux}"
KERNEL_DIR="$WORKDIR/kernel/linux"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$WORKDIR/output"
WIN_OUTPUT_DIR="/mnt/c/repo/razorphone2linux/output"

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
# Step 3b: Apply repo-controlled kernel patches
# -------------------------------------------------------
echo "[3b/6] Applying repo-controlled kernel patches..."
PATCH_DIR="$PROJECT_DIR/kernel-patches"
if [ -d "$PATCH_DIR" ]; then
    while IFS= read -r patch_file; do
        patch_name="$(basename "$patch_file")"
        if git -C "$KERNEL_DIR" apply --recount --reverse --check "$patch_file" >/dev/null 2>&1; then
            echo "  $patch_name already applied."
        elif [ "$patch_name" = "0001-razor-aura-mss-pdr-diagnostics.patch" ] &&
             grep -q "sdm845 mss diag reset" "$KERNEL_DIR/drivers/remoteproc/qcom_q6v5_mss.c" &&
             grep -q "PDM diag:" "$KERNEL_DIR/drivers/soc/qcom/qcom_pd_mapper.c"; then
            echo "  $patch_name already applied (marker check)."
        elif [ "$patch_name" = "0002-razor-aura-mss-crash-reason-deep-diagnostics.patch" ] &&
             grep -q "q6v5_diag_dump_crash_smem" "$KERNEL_DIR/drivers/remoteproc/qcom_q6v5.c"; then
            echo "  $patch_name already applied (marker check)."
        else
            git -C "$KERNEL_DIR" apply --recount --check "$patch_file"
            git -C "$KERNEL_DIR" apply --recount "$patch_file"
            echo "  Applied $patch_name"
        fi
    done < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | sort)
else
    echo "  No kernel-patches directory."
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

# Apply the single canonical config fragment.
CONFIG_FRAGMENT="$PROJECT_DIR/config/razer-aura.config"
if [ ! -f "$CONFIG_FRAGMENT" ]; then
    echo "ERROR: missing canonical config fragment: $CONFIG_FRAGMENT"
    exit 1
fi

echo "Applying Razer Phone 2 config fragment: $CONFIG_FRAGMENT"
sed 's/\r$//' "$CONFIG_FRAGMENT" > /tmp/razer_aura_fragment.config
./scripts/kconfig/merge_config.sh -m .config /tmp/razer_aura_fragment.config

# Keep the Qualcomm Wi-Fi bring-up chain aligned with the postmarketOS SDM845
# reference config. The remoteprocs are modules so userspace can start the
# MSS/RFS path after rootfs services are available, while GLINK/SMD core
# transports stay built in like the working pmOS SDM845 kernels.
./scripts/config --module CFG80211
./scripts/config --module MAC80211
./scripts/config --module ATH10K
./scripts/config --module ATH10K_SNOC
./scripts/config --module QCOM_Q6V5_COMMON
./scripts/config --module QCOM_Q6V5_MSS
./scripts/config --module QCOM_Q6V5_ADSP
./scripts/config --module QCOM_Q6V5_PAS
./scripts/config --disable QCOM_Q6V5_WCSS
./scripts/config --module QCOM_WCNSS_PIL
./scripts/config --module QCOM_RPROC_COMMON
./scripts/config --module QCOM_SYSMON
./scripts/config --enable QCOM_PD_MAPPER
./scripts/config --module QCOM_PD_MAPPER
./scripts/config --module QCOM_PDR_HELPERS
./scripts/config --module QCOM_PDR_MSG
./scripts/config --enable QCOM_RMTFS_MEM
./scripts/config --module QCOM_MDT_LOADER
./scripts/config --module QCOM_QMI_HELPERS
./scripts/config --enable QCOM_AOSS_QMP
./scripts/config --enable RESET_QCOM_AOSS
./scripts/config --module RESET_QCOM_PDC
./scripts/config --enable RPMSG_QCOM_SMD
./scripts/config --enable RPMSG_QCOM_GLINK
./scripts/config --enable RPMSG_QCOM_GLINK_RPM
./scripts/config --module RPMSG_QCOM_GLINK_SMEM
./scripts/config --module QRTR
./scripts/config --module QRTR_SMD
./scripts/config --module QRTR_TUN
./scripts/config --module QRTR_MHI
./scripts/config --module MHI_BUS
./scripts/config --module QCOM_PIL_INFO
./scripts/config --module QCOM_IPA

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
echo "$KERNEL_RELEASE" > "$OUTPUT_DIR/kernel.release"
for module_path in \
    "kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko" \
    "kernel/drivers/net/wireless/ath/ath10k/ath10k_snoc.ko" \
    "kernel/drivers/remoteproc/qcom_q6v5.ko" \
    "kernel/drivers/remoteproc/qcom_q6v5_mss.ko" \
    "kernel/drivers/remoteproc/qcom_q6v5_pas.ko" \
    "kernel/drivers/remoteproc/qcom_wcnss_pil.ko" \
    "kernel/drivers/soc/qcom/qcom_pd_mapper.ko" \
    "kernel/drivers/net/ipa/ipa.ko"; do
    if [ ! -f "$OUTPUT_DIR/modules_install/lib/modules/$KERNEL_RELEASE/$module_path" ]; then
        echo "ERROR: expected SDM845 Wi-Fi/MSS module missing after modules_install: $module_path"
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

mkdir -p "$WIN_OUTPUT_DIR"
copy_aux_output() {
    local src="$1"
    local dst="$2"

    if ! cp -f "$src" "$dst"; then
        echo "  WARNING: failed to copy $(basename "$src") to Windows output."
        echo "           WSL output remains authoritative for boot packaging: $src"
    fi
}

copy_aux_output "$OUTPUT_DIR/Image.gz" "$WIN_OUTPUT_DIR/Image.gz"
copy_aux_output "$OUTPUT_DIR/sdm845-razer-aura.dtb" "$WIN_OUTPUT_DIR/sdm845-razer-aura.dtb"
copy_aux_output "$OUTPUT_DIR/Image.gz-dtb" "$WIN_OUTPUT_DIR/Image.gz-dtb"
copy_aux_output "$OUTPUT_DIR/kernel.release" "$WIN_OUTPUT_DIR/kernel.release"

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
echo "  kernel.release      - Kernel release string for rootfs/boot checks"
echo "  build.log           - Build log"
echo ""
echo "Next: Run bash 03-build-rootfs.sh"
