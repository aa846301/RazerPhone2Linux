#!/bin/bash
# ==========================================================================
# inject-wifi-firmware.sh
# ==========================================================================
# Inject WCN3990 (ath10k) WiFi firmware + Adreno 630 GMU firmware into
# the EXISTING rootfs.img WITHOUT doing a full debootstrap rebuild.
#
# This is useful when:
#   - rootfs is already flashed to the device but WiFi doesn't work
#   - You want to avoid the 40-minute userdata flash until all firmware is ready
#
# After this script, run:
#   fastboot flash userdata output/rootfs-sparse.img
#   fastboot reboot
#
# OR, if Linux is already booted and you have USB/SSH access:
#   sudo apt install linux-firmware
# ==========================================================================

set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
ROOTFS_IMG="$WORKDIR/rootfs/rootfs-noble.img"
MOUNT_DIR="$WORKDIR/rootfs/inject-mnt"
WIN_OUTPUT_DIR="/mnt/c/repo/razorphone2linux/output"
OUTPUT_SPARSE="$WIN_OUTPUT_DIR/rootfs-sparse.img"

LINUX_FW_BASE="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root (sudo)."
    exit 1
fi

if [ ! -f "$ROOTFS_IMG" ]; then
    echo "ERROR: rootfs image not found: $ROOTFS_IMG"
    echo "  Run scripts/03-build-rootfs.sh first."
    exit 1
fi

echo "=== Injecting firmware into existing rootfs ==="
echo "  Source: $ROOTFS_IMG"

mkdir -p "$MOUNT_DIR"

# Clean up on exit
cleanup() {
    umount "$MOUNT_DIR" 2>/dev/null || true
    rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

mount "$ROOTFS_IMG" "$MOUNT_DIR"
echo "  Mounted rootfs at $MOUNT_DIR"

ATH10K_DIR="$MOUNT_DIR/usr/lib/firmware/ath10k/WCN3990/hw1.0"
QCOM_DIR="$MOUNT_DIR/usr/lib/firmware/qcom"
mkdir -p "$ATH10K_DIR" "$QCOM_DIR"

# ── WCN3990 WiFi firmware ──────────────────────────────────────
echo ""
echo "[1/3] Downloading WCN3990 firmware (ath10k_snoc)..."
FAILED_FW=()
for fw_file in firmware-5.bin board.bin board-2.bin; do
    url="${LINUX_FW_BASE}/ath10k/WCN3990/hw1.0/${fw_file}"
    dest="$ATH10K_DIR/$fw_file"
    if wget -q --timeout=30 -O "$dest" "$url"; then
        echo "  OK  $fw_file ($(du -h "$dest" | cut -f1))"
    else
        FAILED_FW+=("$fw_file")
        echo "  FAIL $fw_file"
        rm -f "$dest"
    fi
done

# ── Adreno 630 GMU firmware (open, in linux-firmware) ──────────
echo ""
echo "[2/3] Downloading Adreno 630 GMU firmware..."
if wget -q --timeout=30 -O "$QCOM_DIR/a630_gmu.bin" \
        "${LINUX_FW_BASE}/qcom/a630_gmu.bin"; then
    echo "  OK  a630_gmu.bin ($(du -h "$QCOM_DIR/a630_gmu.bin" | cut -f1))"
else
    echo "  FAIL a630_gmu.bin"
    rm -f "$QCOM_DIR/a630_gmu.bin"
fi

# ── Proprietary firmware (if already extracted) ────────────────
echo ""
echo "[3/3] Checking for proprietary firmware in $WORKDIR/firmware/ ..."
PROP_DEST="$MOUNT_DIR/usr/lib/firmware/qcom/sdm845/Razer/aura"
PROP_SRC="$WORKDIR/firmware/qcom/sdm845/Razer/aura"
if [ -d "$PROP_SRC" ] && [ "$(ls -A "$PROP_SRC" 2>/dev/null)" ]; then
    mkdir -p "$PROP_DEST"
    cp -rv "$PROP_SRC"/* "$PROP_DEST/"
    echo "  Proprietary blobs copied."
else
    echo "  Skipped (run wsl-scripts/extract-qcom-firmware.sh first)."
fi

umount "$MOUNT_DIR"
trap - EXIT

# ── Re-create sparse image ─────────────────────────────────────
echo ""
echo "Converting updated rootfs to sparse image..."
if command -v img2simg &>/dev/null; then
    img2simg "$ROOTFS_IMG" "$OUTPUT_SPARSE"
    echo "  Sparse image: $OUTPUT_SPARSE ($(du -h "$OUTPUT_SPARSE" | cut -f1))"
else
    echo "  img2simg not found. Install with: sudo apt install android-sdk-libsparse-utils"
    echo "  Copying raw image as fallback (fastboot will accept it but it's larger)..."
    cp -v "$ROOTFS_IMG" "$OUTPUT_SPARSE"
fi

echo ""
echo "=== Done. ==="
if [ ${#FAILED_FW[@]} -gt 0 ]; then
    echo "WARNING: Some downloads failed: ${FAILED_FW[*]}"
    echo "  Try manually: wget -O <dest> ${LINUX_FW_BASE}/ath10k/WCN3990/hw1.0/<file>"
fi
echo ""
echo "Flash the updated rootfs:"
echo "  fastboot flash userdata output/rootfs-sparse.img"
echo "  fastboot reboot"
echo ""
echo "Or if Linux is already booted via USB:"
echo "  ssh klipper@192.168.100.2 'sudo apt update && sudo apt install -y linux-firmware'"
