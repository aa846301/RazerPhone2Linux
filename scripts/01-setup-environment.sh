#!/bin/bash
# ==========================================================================
# Razer Phone 2 (aura) - Mainline Linux Build Environment Setup
# ==========================================================================
# This script sets up the complete build environment in WSL Ubuntu 24.04
# for cross-compiling a mainline Linux kernel targeting the Razer Phone 2.
#
# Usage: bash 01-setup-environment.sh
# Must be run inside WSL Ubuntu (not Windows).
# ==========================================================================

set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
KERNEL_DIR="$WORKDIR/kernel/linux"
REFERENCE_DIR="$WORKDIR/reference"
FIRMWARE_DIR="$WORKDIR/firmware"

echo "========================================"
echo " Razer Phone 2 - Build Environment Setup"
echo "========================================"

# -------------------------------------------------------
# Step 1: Install build dependencies
# -------------------------------------------------------
echo "[1/5] Installing build dependencies..."
sudo apt update
sudo apt install -y \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    build-essential bc bison flex \
    libssl-dev libncurses-dev libelf-dev \
    device-tree-compiler \
    debootstrap qemu-user-static \
    rsync git curl wget cpio lz4 \
    python3 python3-pip \
    libgmp-dev libmpc-dev \
    android-sdk-libsparse-utils \
    u-boot-tools \
    kmod

# Install mkbootimg (Android boot image tool)
if ! command -v mkbootimg &>/dev/null; then
    echo "Installing mkbootimg..."
    sudo apt install -y mkbootimg 2>/dev/null || {
        echo "mkbootimg not in apt, installing via pip..."
        pip3 install --break-system-packages mkbootimg 2>/dev/null || \
        pip3 install mkbootimg
    }
fi

# Install adb/fastboot
if ! command -v fastboot &>/dev/null; then
    echo "Installing android-tools for fastboot/adb..."
    sudo apt install -y android-tools-adb android-tools-fastboot 2>/dev/null || \
    sudo apt install -y adb fastboot 2>/dev/null || {
        echo "WARNING: Could not install fastboot/adb. Install manually."
    }
fi

echo "[1/5] Build dependencies installed."

# -------------------------------------------------------
# Step 2: Create directory structure
# -------------------------------------------------------
echo "[2/5] Creating directory structure..."
mkdir -p "$WORKDIR"/{kernel,reference,firmware,rootfs,output,scripts}
mkdir -p "$FIRMWARE_DIR"/{qcom/sdm845/Razer/aura,ath10k/WCN3990/hw1.0}

echo "[2/5] Directory structure created."

# -------------------------------------------------------
# Step 3: Clone mainline SDM845 kernel
# -------------------------------------------------------
echo "[3/5] Cloning mainline SDM845 Linux kernel..."
if [ ! -d "$KERNEL_DIR" ]; then
    git clone --depth=1 https://gitlab.com/sdm845-mainline/linux.git \
        -b sdm845/6.16-dev "$KERNEL_DIR"
    echo "Kernel cloned to $KERNEL_DIR"
else
    echo "Kernel already exists at $KERNEL_DIR, skipping clone."
    cd "$KERNEL_DIR"
    git pull || echo "Pull failed, using existing code."
fi

# -------------------------------------------------------
# Step 4: Clone Razer Android kernel for reference
# -------------------------------------------------------
echo "[4/5] Cloning Razer Phone 2 Android kernel (reference)..."
if [ ! -d "$REFERENCE_DIR/android_kernel_razer_aura" ]; then
    git clone --depth=1 https://github.com/ASKSAP/android_kernel_razer_aura.git \
        "$REFERENCE_DIR/android_kernel_razer_aura"
    echo "Reference kernel cloned."
else
    echo "Reference kernel already exists, skipping."
fi

# -------------------------------------------------------
# Step 5: Verify cross-compiler
# -------------------------------------------------------
echo "[5/5] Verifying cross-compilation toolchain..."
CROSS_COMPILE_VER=$(aarch64-linux-gnu-gcc --version | head -1)
echo "Cross compiler: $CROSS_COMPILE_VER"

echo ""
echo "========================================"
echo " Environment setup complete!"
echo "========================================"
echo ""
echo "Workspace: $WORKDIR"
echo "Kernel:    $KERNEL_DIR"
echo "Reference: $REFERENCE_DIR"
echo ""
echo "Next steps:"
echo "  1. Copy device tree:  cp <project>/dts/sdm845-razer-aura.dts $KERNEL_DIR/arch/arm64/boot/dts/qcom/"
echo "  2. Copy panel driver: cp <project>/panel-driver/panel-novatek-nt36830.c $KERNEL_DIR/drivers/gpu/drm/panel/"
echo "  3. Run: bash 02-build-kernel.sh"
echo ""
echo "IMPORTANT: You need to extract firmware blobs from Razer Phone 2 stock ROM"
echo "  and place them in: $FIRMWARE_DIR/"
echo "  Required firmware:"
echo "    - qcom/sdm845/Razer/aura/adsp.mbn"
echo "    - qcom/sdm845/Razer/aura/cdsp.mbn"
echo "    - qcom/sdm845/Razer/aura/a630_zap.mbn"
echo "    - qcom/sdm845/Razer/aura/venus.mbn"
echo "    - qcom/sdm845/Razer/aura/mba.mbn"
echo "    - qcom/sdm845/Razer/aura/modem.mbn"
echo "    - qcom/sdm845/Razer/aura/slpi.mbn"
echo "    - qcom/sdm845/Razer/aura/ipa_fws.mbn"
echo "    - ath10k/WCN3990/hw1.0/board.bin"
echo "    - ath10k/WCN3990/hw1.0/firmware-5.bin"
