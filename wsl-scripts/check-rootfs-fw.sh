#!/bin/bash
set -euo pipefail
REAL_HOME=$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)
MNT="$REAL_HOME/razorphone2linux/fw-extract-tmp/rootfs-verify-mnt"
ROOTFS="$REAL_HOME/razorphone2linux/rootfs/rootfs-noble.img"
PKGDIR="$REAL_HOME/razorphone2linux/fw-extract-tmp/debs"

mkdir -p "$MNT"
trap "umount '$MNT' 2>/dev/null || true" EXIT
mount "$ROOTFS" "$MNT"

echo "=== /lib/firmware/ath10k/WCN3990/hw1.0/ ==="
ls "$MNT/lib/firmware/ath10k/WCN3990/hw1.0/" 2>/dev/null || echo "(not found)"

echo ""
echo "=== /usr/lib/firmware/ath10k/WCN3990/hw1.0/ ==="
ls "$MNT/usr/lib/firmware/ath10k/WCN3990/hw1.0/" 2>/dev/null || echo "(not found)"

echo ""
echo "=== debs/ directory ==="
ls "$PKGDIR/" 2>/dev/null
