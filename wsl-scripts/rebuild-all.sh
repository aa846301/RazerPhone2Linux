#!/bin/bash
# ==========================================================================
# rebuild-all.sh  (run in WSL)
# ==========================================================================
# Rebuild kernel + DTB + observable boot image in one shot.
# Does NOT rebuild the full rootfs (that's a separate 03-build-rootfs.sh).
#
# Usage (in WSL):
#   bash /mnt/c/repo/razorphone2linux/wsl-scripts/rebuild-all.sh
#
# Then on Windows:
#   python3 /mnt/c/repo/razorphone2linux/wsl-scripts/make-vbmeta-disabled.py
#   .\scripts\07-flash-observable.ps1
# ==========================================================================

set -euo pipefail

WIN_REPO="/mnt/c/repo/razorphone2linux"
WORKDIR="$HOME/razorphone2linux"

echo "=== [1/3] Rebuild kernel + DTB ==="
bash "$WIN_REPO/rebuild-kernel.sh"

echo ""
echo "=== [2/3] Regenerate vbmeta_disabled.img ==="
python3 "$WIN_REPO/wsl-scripts/make-vbmeta-disabled.py"

echo ""
echo "=== [3/3] Package observable boot image ==="
bash "$WIN_REPO/scripts/04-make-observable-boot.sh"

echo ""
echo "============================================"
echo " All artifacts ready in output/"
echo "  boot-observable.img  – flash to boot_a"
echo "  vbmeta_disabled.img  – flash to vbmeta"
echo "  rootfs-sparse.img    – already on device"
echo ""
echo " On Windows:"
echo "   .\\scripts\\07-flash-observable.ps1"
echo " (skips userdata reflash – only boot_a + vbmeta + reboot)"
echo "============================================"
