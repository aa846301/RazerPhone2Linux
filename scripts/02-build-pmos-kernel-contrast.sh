#!/bin/bash
# ==========================================================================
# Razer Phone 2 (aura) - postmarketOS SDM845 Kernel Contrast Build
# ==========================================================================
# Builds the postmarketOS/sdm845-mainline 6.11 kernel with the Razer aura DTS.
# This is an explicit WiFi/MSS contrast artifact, not the normal mainline
# kernel path. Enter through:
#
#   bash scripts/build-all.sh pmos-kernel
#   bash scripts/build-all.sh pmos-contrast
# ==========================================================================

set -euo pipefail

WORKDIR="${RAZER_WORKDIR:-$HOME/razorphone2linux}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/config/build.env"
IMAGE_PROFILE="${RAZER_IMAGE_PROFILE:-base}"
KERNEL_DIR="${PMOS_KERNEL_DIR:-$WORKDIR/kernel/pmos-sdm845}"
OUTPUT_DIR="$WORKDIR/output/$IMAGE_PROFILE"
WIN_OUTPUT_DIR="$PROJECT_DIR/output/$IMAGE_PROFILE"
PMOS_TAG="${PMOS_TAG:-sdm845-6.11}"
PMOS_REPO="${PMOS_REPO:-https://gitlab.com/sdm845-mainline/linux.git}"
PMOS_CONFIG="$PROJECT_DIR/.tmp/pmos-reference/pmaports/device/community/linux-postmarketos-qcom-sdm845/config-postmarketos-qcom-sdm845.aarch64"

mkdir -p "$OUTPUT_DIR" "$WIN_OUTPUT_DIR"

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
echo " Razer Phone 2 - pmOS SDM845 Kernel Contrast"
echo "========================================"
echo "Kernel dir: $KERNEL_DIR"
echo "pmOS tag:   $PMOS_TAG"
echo "Parallel jobs: $BUILD_JOBS"
echo ""

if [ ! -f "$PMOS_CONFIG" ]; then
    echo "ERROR: missing pmOS config:"
    echo "  $PMOS_CONFIG"
    echo "Run the SDM845 reference-image/pmaports preparation first."
    exit 1
fi

if [ ! -d "$KERNEL_DIR/.git" ]; then
    mkdir -p "$(dirname "$KERNEL_DIR")"
    git clone --depth=1 --branch "$PMOS_TAG" "$PMOS_REPO" "$KERNEL_DIR"
fi

TARGET_COMMIT="$(git -C "$KERNEL_DIR" rev-list -n1 "$PMOS_TAG" 2>/dev/null || true)"
CURRENT_COMMIT="$(git -C "$KERNEL_DIR" rev-parse HEAD)"
if [ -n "$TARGET_COMMIT" ] && [ "$CURRENT_COMMIT" != "$TARGET_COMMIT" ]; then
    echo "ERROR: $KERNEL_DIR is not at $PMOS_TAG."
    echo "  current: $CURRENT_COMMIT"
    echo "  target:  $TARGET_COMMIT"
    echo "Use a clean PMOS_KERNEL_DIR or manually switch the contrast tree."
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$WIN_OUTPUT_DIR"

echo "[1/6] Installing Razer DTS into pmOS kernel tree..."
cp -v "$PROJECT_DIR/dts/sdm845-razer-aura.dts" \
    "$KERNEL_DIR/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts"

# Linux 6.11's SDM845 DSI PHY binding headers do not expose the newer DSI
# byte/pixel PLL clock constants used only by our disabled DSI1 node. Keep the
# simplefb/disabled-DSI contrast identical while making the DTS parse on pmOS.
python3 - "$KERNEL_DIR/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    '\n\t/* DSI1 is slave, so use DSI0 clocks */\n'
    '\tassigned-clock-parents = <&mdss_dsi0_phy DSI_BYTE_PLL_CLK>,\n'
    '\t\t\t\t <&mdss_dsi0_phy DSI_PIXEL_PLL_CLK>;\n',
    '\n'
)
path.write_text(text)
PY

DTS_MAKEFILE="$KERNEL_DIR/arch/arm64/boot/dts/qcom/Makefile"
if ! grep -q "sdm845-razer-aura.dtb" "$DTS_MAKEFILE"; then
    printf '\ndtb-$(CONFIG_ARCH_QCOM) += sdm845-razer-aura.dtb\n' >> "$DTS_MAKEFILE"
    echo "  Added sdm845-razer-aura.dtb to pmOS DTS Makefile."
else
    echo "  sdm845-razer-aura.dtb already in pmOS DTS Makefile."
fi

echo "[2/6] Applying pmOS SDM845 config..."
cp -v "$PMOS_CONFIG" "$KERNEL_DIR/.config"
cd "$KERNEL_DIR"

echo "[2b/6] Applying pmOS contrast diagnostic patches..."
PMOS_PATCH_DIR="$PROJECT_DIR/kernel-patches/pmos-contrast"
if [ -d "$PMOS_PATCH_DIR" ]; then
    while IFS= read -r patch_file; do
        patch_name="$(basename "$patch_file")"
        if [ "${PMOS_APPLY_DIAG_PATCHES:-0}" = "1" ]; then
            if git -C "$KERNEL_DIR" apply --recount --reverse --check "$patch_file" >/dev/null 2>&1; then
                echo "  $patch_name already applied."
            else
                git -C "$KERNEL_DIR" apply --recount --check "$patch_file"
                git -C "$KERNEL_DIR" apply --recount "$patch_file"
                echo "  Applied $patch_name"
            fi
        else
            if git -C "$KERNEL_DIR" apply --recount --reverse --check "$patch_file" >/dev/null 2>&1; then
                git -C "$KERNEL_DIR" apply --recount --reverse "$patch_file"
                echo "  Removed $patch_name (set PMOS_APPLY_DIAG_PATCHES=1 to enable)."
            else
                echo "  Skipped $patch_name (set PMOS_APPLY_DIAG_PATCHES=1 to enable)."
            fi
        fi
    done < <(find "$PMOS_PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | sort)
else
    echo "  No pmOS contrast patch directory."
fi

make olddefconfig

echo "[3/6] Building pmOS kernel, Razer DTB, and modules..."
if ! make -j"$BUILD_JOBS" Image.gz qcom/sdm845-razer-aura.dtb modules 2>&1 | tee "$OUTPUT_DIR/build-pmos-contrast.log"; then
    echo '' | tee -a "$OUTPUT_DIR/build-pmos-contrast.log"
    echo 'Parallel pmOS build failed under WSL, retrying with -j1...' | tee -a "$OUTPUT_DIR/build-pmos-contrast.log"
    make olddefconfig 2>&1 | tee -a "$OUTPUT_DIR/build-pmos-contrast.log"
    make prepare modules_prepare 2>&1 | tee -a "$OUTPUT_DIR/build-pmos-contrast.log"
    make -j1 Image.gz qcom/sdm845-razer-aura.dtb modules 2>&1 | tee -a "$OUTPUT_DIR/build-pmos-contrast.log"
fi

echo "[4/6] Installing pmOS modules..."
rm -rf "$OUTPUT_DIR/modules_install"
make INSTALL_MOD_PATH="$OUTPUT_DIR/modules_install" modules_install

KERNEL_RELEASE="$(make -s kernelrelease)"
echo "$KERNEL_RELEASE" > "$OUTPUT_DIR/kernel.release"
echo "pmos-sdm845-contrast" > "$OUTPUT_DIR/kernel.flavor"

MODULE_SRC="$OUTPUT_DIR/modules_install/lib/modules/$KERNEL_RELEASE"
for module_path in \
    "kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko" \
    "kernel/drivers/net/wireless/ath/ath10k/ath10k_snoc.ko" \
    "kernel/drivers/remoteproc/qcom_q6v5_mss.ko" \
    "kernel/drivers/soc/qcom/qcom_pd_mapper.ko"; do
    if [ ! -f "$MODULE_SRC/$module_path" ] && [ ! -f "$MODULE_SRC/$module_path.zst" ]; then
        echo "ERROR: expected pmOS WiFi/MSS module missing after modules_install: $module_path"
        exit 1
    fi
done

echo "[5/6] Collecting pmOS contrast outputs..."
cp -v arch/arm64/boot/Image.gz "$OUTPUT_DIR/Image.gz"
cp -v arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb "$OUTPUT_DIR/sdm845-razer-aura.dtb"
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb \
    > "$OUTPUT_DIR/Image.gz-dtb"
cp -v .config "$OUTPUT_DIR/config-pmos-sdm845-contrast"

cp -f "$OUTPUT_DIR/Image.gz" "$WIN_OUTPUT_DIR/Image.gz"
cp -f "$OUTPUT_DIR/sdm845-razer-aura.dtb" "$WIN_OUTPUT_DIR/sdm845-razer-aura.dtb"
cp -f "$OUTPUT_DIR/Image.gz-dtb" "$WIN_OUTPUT_DIR/Image.gz-dtb"
cp -f "$OUTPUT_DIR/kernel.release" "$WIN_OUTPUT_DIR/kernel.release"
cp -f "$OUTPUT_DIR/kernel.flavor" "$WIN_OUTPUT_DIR/kernel.flavor"
cp -f "$OUTPUT_DIR/config-pmos-sdm845-contrast" "$WIN_OUTPUT_DIR/config-pmos-sdm845-contrast"

echo "[6/6] pmOS contrast kernel ready."
echo ""
echo "Kernel release: $KERNEL_RELEASE"
echo "Outputs in: $OUTPUT_DIR"
echo "Next for flashable artifact:"
echo "  bash scripts/build-all.sh pmos-contrast"
