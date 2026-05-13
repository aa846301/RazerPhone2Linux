#!/bin/bash
# ==========================================================================
# extract-qcom-firmware.sh
# ==========================================================================
# Extract proprietary Qualcomm firmware blobs from a Razer Phone 2 stock
# Android ROM image and place them in the correct paths for mainline Linux.
#
# Required input: a directory containing the extracted stock ROM partitions
# (usually obtained by extracting the factory/OTA zip, OR by pulling from
# a running Android device via adb).
#
# Usage:
#   # Option A – From an extracted factory/OTA zip (most common):
#   ./extract-qcom-firmware.sh /path/to/extracted_rom_dir
#
#   # Option B – Pull directly from a running Android device via adb:
#   ./extract-qcom-firmware.sh --adb
#
# Output:
#   ~/razorphone2linux/firmware/qcom/sdm845/Razer/aura/   ← proprietary
#   ~/razorphone2linux/firmware/ath10k/WCN3990/hw1.0/     ← WiFi (from ROM)
#
# After running this script, rebuild the rootfs:
#   sudo bash /mnt/c/repo/razorphone2linux/scripts/03-build-rootfs.sh
# ==========================================================================

set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
OUTPUT_FW="$WORKDIR/firmware"
WIN_OUTPUT_FW="/mnt/c/repo/razorphone2linux/firmware"

# Destination paths that match DTS firmware-name properties:
#   adsp_pas:  qcom/sdm845/Razer/aura/adsp.mbn
#   cdsp_pas:  qcom/sdm845/Razer/aura/cdsp.mbn
#   gpu:       qcom/sdm845/Razer/aura/a630_zap.mbn
#   venus:     qcom/sdm845/Razer/aura/venus.mbn

DEST_DIR="$OUTPUT_FW/qcom/sdm845/Razer/aura"
ATH10K_DEST="$OUTPUT_FW/ath10k/WCN3990/hw1.0"

mkdir -p "$DEST_DIR" "$ATH10K_DEST"

# ──────────────────────────────────────────────────────────────
# Pull firmware via adb from a running Android device
# ──────────────────────────────────────────────────────────────
pull_via_adb() {
    echo "Pulling firmware from device via adb..."
    if ! command -v adb &>/dev/null; then
        echo "ERROR: adb not found. Install android-tools-adb."
        exit 1
    fi

    adb wait-for-device
    adb root 2>/dev/null || true
    sleep 1

    echo "  Pulling ADSP firmware..."
    adb pull /vendor/firmware_mnt/image/adsp.mbn "$DEST_DIR/adsp.mbn" || \
    adb pull /firmware/image/adsp.mbn             "$DEST_DIR/adsp.mbn" || \
        echo "  WARNING: adsp.mbn not found"

    echo "  Pulling CDSP firmware..."
    adb pull /vendor/firmware_mnt/image/cdsp.mbn "$DEST_DIR/cdsp.mbn" || \
    adb pull /firmware/image/cdsp.mbn             "$DEST_DIR/cdsp.mbn" || \
        echo "  WARNING: cdsp.mbn not found"

    echo "  Pulling GPU zap shader..."
    adb pull /vendor/firmware_mnt/image/a630_zap.mbn "$DEST_DIR/a630_zap.mbn" || \
    adb pull /lib/firmware/a630_zap.mbn               "$DEST_DIR/a630_zap.mbn" || \
    adb pull /vendor/lib/firmware/a630_zap.mbn         "$DEST_DIR/a630_zap.mbn" || \
        echo "  WARNING: a630_zap.mbn not found"

    echo "  Pulling Venus (video codec) firmware..."
    adb pull /vendor/firmware_mnt/image/venus.mbn "$DEST_DIR/venus.mbn" || \
    adb pull /firmware/image/venus.mbn             "$DEST_DIR/venus.mbn" || \
        echo "  WARNING: venus.mbn not found"

    echo "  Pulling WCN3990 WiFi firmware..."
    adb pull /vendor/firmware_mnt/image/wcnss.mbn \
        "$ATH10K_DEST/firmware-5.bin" 2>/dev/null || true
    # Also try the ath10k paths in vendor
    for src in \
        /vendor/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin \
        /system/etc/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin; do
        adb pull "$src" "$ATH10K_DEST/firmware-5.bin" 2>/dev/null && break || true
    done

    echo "  adb pull complete."
}

# ──────────────────────────────────────────────────────────────
# Extract firmware from an unpacked factory/OTA directory
# ──────────────────────────────────────────────────────────────
extract_from_dir() {
    local rom_dir="$1"
    echo "Searching for firmware in: $rom_dir"

    # Candidate source paths inside the ROM directory tree
    find_fw() {
        local name="$1"
        find "$rom_dir" \
            -type f \
            \( -name "$name" -o -name "${name%.mbn}.MBN" \) \
            2>/dev/null | head -1
    }

    copy_fw() {
        local src dest_name
        src=$(find_fw "$1")
        dest_name="$2"
        if [ -n "$src" ]; then
            cp -v "$src" "$DEST_DIR/$dest_name"
        else
            echo "  WARNING: $1 not found in $rom_dir"
        fi
    }

    copy_fw "adsp.mbn"     "adsp.mbn"
    copy_fw "cdsp.mbn"     "cdsp.mbn"
    copy_fw "a630_zap.mbn" "a630_zap.mbn"
    copy_fw "venus.mbn"    "venus.mbn"

    # WCN3990 WiFi firmware
    local ath10k_src
    ath10k_src=$(find "$rom_dir" -path "*/ath10k/WCN3990/hw1.0/firmware-5.bin" 2>/dev/null | head -1)
    if [ -n "$ath10k_src" ]; then
        cp -rv "$(dirname "$ath10k_src")"/* "$ATH10K_DEST/"
        echo "  Copied ath10k WCN3990 firmware."
    else
        echo "  NOTE: ath10k WCN3990 not found in ROM dir (will use linux-firmware fallback)."
    fi
}

# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────
if [ "${1:-}" = "--adb" ]; then
    pull_via_adb
elif [ -n "${1:-}" ]; then
    if [ ! -d "$1" ]; then
        echo "ERROR: Directory not found: $1"
        exit 1
    fi
    extract_from_dir "$1"
else
    cat << USAGE
Usage:
  $0 /path/to/extracted_rom_directory   # from factory/OTA zip
  $0 --adb                              # pull from a running Android device

How to get the ROM directory:
  1. Download Razer Phone 2 factory/OTA image from Razer support site
  2. Unzip it:  unzip AURA_OTA_*.zip -d rom_extracted/
  3. Run:       $0 rom_extracted/

Or if Android is still running on the device:
  $0 --adb
USAGE
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
echo ""
echo "=== Firmware extraction complete ==="
echo "Files in $DEST_DIR:"
ls -lh "$DEST_DIR" 2>/dev/null || echo "  (empty)"

echo "Files in $ATH10K_DEST:"
ls -lh "$ATH10K_DEST" 2>/dev/null || echo "  (empty)"

echo ""
echo "Next step: sync to Windows output dir and rebuild rootfs:"
echo "  rsync -av $OUTPUT_FW/ $WIN_OUTPUT_FW/"
echo "  sudo bash /mnt/c/repo/razorphone2linux/scripts/03-build-rootfs.sh"
echo ""
echo "Or to inject into the EXISTING rootfs WITHOUT a full rebuild:"
echo "  sudo bash /mnt/c/repo/razorphone2linux/wsl-scripts/inject-wifi-firmware.sh"
