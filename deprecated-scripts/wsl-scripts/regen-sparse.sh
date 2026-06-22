#!/bin/bash
# Regenerate sparse from noble.img via WSL local path (avoids NTFS write issues)
set -e
NOBLE="/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img"
WSL_SPARSE="/home/dinochang/razorphone2linux/output/rootfs-sparse.img"
WIN_SPARSE="/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img"
WIN_BOOT="/mnt/c/repo/razorphone2linux/output/boot.img"
WSL_BOOT="/home/dinochang/razorphone2linux/output/boot.img"

echo "=== Regenerate sparse + copy boot.img ==="
echo ""

# Quick VID check on noble.img before converting
MNT=/home/dinochang/rootfs-verify-mnt
umount "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
mount -o loop,ro "$NOBLE" "$MNT"
VID=$(grep 'idVendor' "$MNT/usr/local/bin/usb-gadget-setup.sh" 2>/dev/null | grep -o '0x[0-9a-fA-F]*' | head -1 || echo "MISSING")
echo "  noble.img VID in usb-gadget-setup.sh: $VID"
[ "$VID" = "0x0525" ] || { echo "ERROR: VID is not 0x0525!"; umount "$MNT"; exit 1; }
umount "$MNT"

echo "[1/3] img2simg to WSL local path..."
img2simg "$NOBLE" "$WSL_SPARSE"
echo "  WSL sparse: $(ls -lh $WSL_SPARSE | awk '{print $5, $6, $7, $8}')"

echo "[2/3] Copying sparse to Windows..."
cp -f "$WSL_SPARSE" "$WIN_SPARSE"
echo "  Windows sparse: $(ls -lh $WIN_SPARSE | awk '{print $5, $6, $7, $8}')"

echo "[3/3] Copying boot.img to Windows..."
cp -f "$WSL_BOOT" "$WIN_BOOT"
echo "  Windows boot.img: $(ls -lh $WIN_BOOT | awk '{print $5, $6, $7, $8}')"

echo ""
echo "=== DONE ==="
echo "Flash both files this time (boot.img VID also fixed):"
echo "  fastboot flash boot output\\boot.img"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
