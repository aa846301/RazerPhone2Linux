#!/bin/bash
# ==========================================================================
# Razer Phone 2 (aura) - Flash Script
# ==========================================================================
# Flashes the built images to the Razer Phone 2 via fastboot.
#
# Usage: bash 05-flash.sh [--unlock]
#   --unlock: Also unlock the bootloader (WILL WIPE ALL DATA)
#
# Prerequisites:
#   - Phone connected via USB in fastboot mode
#   - fastboot tool installed
#   - All images built (boot.img, rootfs-sparse.img, vbmeta_disabled.img)
# ==========================================================================

set -euo pipefail

WORKDIR="$HOME/razorphone2linux"
OUTPUT_DIR="$WORKDIR/output"

BOOT_IMG="$OUTPUT_DIR/boot.img"
ROOTFS_IMG="$OUTPUT_DIR/rootfs-sparse.img"
VBMETA_IMG="$OUTPUT_DIR/vbmeta_disabled.img"

echo "========================================"
echo " Razer Phone 2 - Flash Tool"
echo "========================================"

# Check fastboot
if ! command -v fastboot &>/dev/null; then
    echo "ERROR: fastboot not found. Install with: sudo apt install android-tools-fastboot"
    exit 1
fi

# Check device connection
echo "Checking for device in fastboot mode..."
DEVICE=$(fastboot devices 2>/dev/null | head -1)
if [ -z "$DEVICE" ]; then
    echo "ERROR: No device found in fastboot mode."
    echo ""
    echo "To enter fastboot mode:"
    echo "  1. Power off the phone"
    echo "  2. Hold Volume Down + Power until fastboot screen"
    echo "  OR: adb reboot bootloader"
    exit 1
fi
echo "  Device found: $DEVICE"

# Check required images
for img in "$BOOT_IMG" "$ROOTFS_IMG"; do
    if [ ! -f "$img" ]; then
        echo "ERROR: Required image not found: $img"
        exit 1
    fi
done

# Unlock bootloader if requested
if [ "${1:-}" = "--unlock" ]; then
    echo ""
    echo "WARNING: Unlocking bootloader will WIPE ALL DATA on the device!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        echo "Unlocking bootloader..."
        fastboot oem unlock || fastboot flashing unlock
        echo "Bootloader unlocked. Device may reboot."
        echo "Re-enter fastboot mode and run this script again without --unlock."
        exit 0
    else
        echo "Aborted."
        exit 1
    fi
fi

echo ""
echo "This will flash the following images:"
echo "  boot.img     -> boot_a partition ($(du -h "$BOOT_IMG" | cut -f1))"
echo "  rootfs       -> userdata partition ($(du -h "$ROOTFS_IMG" | cut -f1))"
if [ -f "$VBMETA_IMG" ]; then
    echo "  vbmeta       -> vbmeta_a partition"
fi
echo ""
read -p "Proceed with flashing? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Flash boot image
echo ""
echo "[1/3] Flashing boot image..."
fastboot flash boot "$BOOT_IMG"
echo "  Boot image flashed."

# Flash rootfs to userdata
echo "[2/3] Flashing rootfs to userdata (this may take several minutes)..."
fastboot flash userdata "$ROOTFS_IMG"
echo "  Rootfs flashed."

# Flash vbmeta with verification disabled
if [ -f "$VBMETA_IMG" ]; then
    echo "[3/3] Flashing vbmeta (disabled verification)..."
    fastboot --disable-verity --disable-verification flash vbmeta "$VBMETA_IMG"
    echo "  Vbmeta flashed."
else
    echo "[3/3] Skipping vbmeta (file not found)."
    echo "  WARNING: Boot may fail without disabled verification."
fi

echo ""
echo "========================================"
echo " Flashing complete!"
echo "========================================"
echo ""
echo "Rebooting device..."
fastboot reboot

echo ""
echo "The device should now boot into mainline Linux."
echo ""
echo "First boot may take 1-2 minutes (filesystem resize)."
echo ""
echo "Access methods:"
echo "  1. USB Serial: screen /dev/ttyACM0 115200 (from host PC)"
echo "  2. SSH via WiFi: ssh klipper@<ip_address>"
echo "  3. Touch screen: KlipperScreen should auto-start"
echo ""
echo "Default credentials: klipper / klipper"
echo "CHANGE PASSWORDS IMMEDIATELY after first login!"
