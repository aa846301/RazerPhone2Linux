#!/bin/bash
# ==========================================================================
# verify-and-resparse.sh  (run as root in WSL)
# ==========================================================================
# Verify the existing rootfs-noble.img, fix any ext4 errors, re-create the
# sparse image with the correct block size, and sync to the Windows output.
#
# Usage:
#   sudo bash /mnt/c/repo/razorphone2linux/wsl-scripts/verify-and-resparse.sh
# ==========================================================================

set -euo pipefail

# Resolve actual user home dir (works with sudo)
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi
WORKDIR="$USER_HOME/razorphone2linux"
ROOTFS_IMG="$WORKDIR/rootfs/rootfs-noble.img"
SPARSE_IMG="$WORKDIR/output/rootfs-sparse.img"
WIN_OUT="/mnt/c/repo/razorphone2linux/output"
MOUNT_DIR="$WORKDIR/rootfs/verify-mnt"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root (sudo)."
    exit 1
fi

echo "=== Step 1: Check rootfs-noble.img ==="
if [ ! -f "$ROOTFS_IMG" ]; then
    echo "ERROR: $ROOTFS_IMG not found."
    echo "The full rootfs was never built.  Run:"
    echo "  sudo bash /mnt/c/repo/razorphone2linux/scripts/03-build-rootfs.sh"
    exit 1
fi

IMGSIZE=$(du -h "$ROOTFS_IMG" | cut -f1)
echo "  Found: $ROOTFS_IMG ($IMGSIZE)"

# Check magic
file "$ROOTFS_IMG"

# Confirm it's ext4
if ! file "$ROOTFS_IMG" | grep -qi ext; then
    echo "ERROR: $ROOTFS_IMG does not appear to be an ext4 filesystem."
    echo "It may be an Android sparse image. Converting back to raw first..."
    TMP_RAW=$(mktemp --suffix=.img)
    simg2img "$ROOTFS_IMG" "$TMP_RAW"
    mv "$TMP_RAW" "$ROOTFS_IMG"
    echo "  Converted to raw ext4."
    file "$ROOTFS_IMG"
fi

echo ""
echo "=== Step 2: Check ext4 filesystem integrity ==="
# -n = dry-run (no changes), -f = force check even if marked clean
e2fsck -n "$ROOTFS_IMG" 2>&1 | tail -20

echo ""
echo "=== Step 3: Fix any ext4 errors ==="
# -p = auto-repair non-interactive, -f = force
e2fsck -p -f "$ROOTFS_IMG" 2>&1 | tail -20 || true
echo "  e2fsck complete."

echo ""
echo "=== Step 4: Mount and verify /sbin/init ==="
mkdir -p "$MOUNT_DIR"
mount -o loop,ro "$ROOTFS_IMG" "$MOUNT_DIR"

echo "  Filesystem label: $(e2label "$ROOTFS_IMG" 2>/dev/null || echo '(no label)')"
echo "  Disk usage: $(df -h "$MOUNT_DIR" | tail -1)"
echo ""

# Check init path (Ubuntu Noble merged-usr)
echo "  Checking init paths:"
for p in sbin/init usr/sbin/init usr/lib/systemd/systemd; do
    full="$MOUNT_DIR/$p"
    if [ -e "$full" ]; then
        echo "  FOUND: /$p -> $(readlink -f "$full" 2>/dev/null || echo '(not a symlink)')"
    else
        echo "  missing: /$p"
    fi
done

echo ""
echo "  Checking key directories:"
ls -la "$MOUNT_DIR/" | head -20
echo "  /etc/os-release:"
cat "$MOUNT_DIR/etc/os-release" 2>/dev/null || echo "  (not found)"

umount "$MOUNT_DIR"
echo "  Unmounted."

echo ""
echo "=== Step 4b: Final e2fsck to clean any dirty state from verification mount ==="
# WSL2 ro-mount may leave needs_recovery flag in superblock; clear it now
e2fsck -f -p "$ROOTFS_IMG" 2>&1 | tail -5 || true
echo "  Final e2fsck complete."

echo ""
echo "=== Step 5: Re-create sparse image (block size 4096) ==="

# Ensure img2simg is available
if ! command -v img2simg &>/dev/null; then
    echo "  Installing android-sdk-libsparse-utils..."
    apt-get install -y android-sdk-libsparse-utils
fi

mkdir -p "$WORKDIR/output"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG" 4096
SPARSESIZE=$(du -h "$SPARSE_IMG" | cut -f1)
echo "  Created: $SPARSE_IMG ($SPARSESIZE)"

# Verify the sparse image header
file "$SPARSE_IMG"
if ! file "$SPARSE_IMG" | grep -qi sparse; then
    echo "WARNING: output does not look like an Android sparse image."
    echo "         fastboot may still accept raw ext4, but check the image."
fi

echo ""
echo "=== Step 6: Sync to Windows output ==="
mkdir -p "$WIN_OUT"
cp -fv "$SPARSE_IMG" "$WIN_OUT/rootfs-sparse.img"

echo ""
echo "============================================"
echo " Done. rootfs-sparse.img is ready."
echo " Size: $(du -h "$WIN_OUT/rootfs-sparse.img" | cut -f1)"
echo ""
echo " Flash to device:"
echo "   Device must be in fastboot mode first."
echo "   On Windows, run:"
echo "     fastboot flash userdata output\\rootfs-sparse.img"
echo "     fastboot reboot"
echo " OR use the full script (also reflashes boot_a):"
echo "     .\\scripts\\07-flash-observable.ps1"
echo "============================================"
