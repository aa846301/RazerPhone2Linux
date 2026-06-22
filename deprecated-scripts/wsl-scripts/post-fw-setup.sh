#!/bin/bash
# post-fw-setup.sh
# 1. Verify firmware was injected into rootfs
# 2. Install linux-firmware (WCN3990 ath10k + other missing) into rootfs
# 3. Copy updated DTB to output/ and rebuild boot image
set -euo pipefail

REAL_HOME=$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)
ROOTFS="$REAL_HOME/razorphone2linux/rootfs/rootfs-noble.img"
MNT="$REAL_HOME/razorphone2linux/fw-extract-tmp/rootfs-verify-mnt"
WIN_DIR=/mnt/c/repo/razorphone2linux

mkdir -p "$MNT"
cleanup() { umount "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

# ── Step 1: Verify firmware in rootfs ─────────────────────────
echo "=== [1/3] Verifying firmware in rootfs ==="
mount "$ROOTFS" "$MNT"
echo "Firmware files injected:"
ls -lh "$MNT/usr/lib/firmware/qcom/sdm845/Razer/aura/" 2>/dev/null || echo "  MISSING - injection may have failed!"
echo ""
echo "ATH10K dir:"
ls "$MNT/usr/lib/firmware/ath10k/WCN3990/hw1.0/" 2>/dev/null || echo "  (empty)"
umount "$MNT"

# ── Step 2: Install firmware + arm64 binaries into rootfs ─────────────────
echo ""
echo "=== [2/3] Installing packages into rootfs ==="
mount "$ROOTFS" "$MNT"

PKGDIR="$REAL_HOME/razorphone2linux/fw-extract-tmp/debs"
mkdir -p "$PKGDIR"

# linux-firmware contains only firmware blobs (arch-independent)
# Extract the already-downloaded amd64 deb - firmware files are the same
FW_DEB=$(ls "$PKGDIR"/linux-firmware_*.deb 2>/dev/null | head -1)
if [ -n "$FW_DEB" ]; then
    echo "  Extracting linux-firmware from: $(basename "$FW_DEB")"
    dpkg-deb -x "$FW_DEB" "$MNT"
    echo "  WCN3990 firmware:"
    ls "$MNT/usr/lib/firmware/ath10k/WCN3990/hw1.0/" 2>/dev/null || echo "  (not found in linux-firmware)"
else
    echo "  WARNING: linux-firmware deb not found, downloading..."
    cd "$PKGDIR" && apt-get download linux-firmware 2>&1 | tail -3
    FW_DEB=$(ls "$PKGDIR"/linux-firmware_*.deb 2>/dev/null | head -1)
    [ -n "$FW_DEB" ] && dpkg-deb -x "$FW_DEB" "$MNT" || echo "  ERROR: could not get linux-firmware"
fi

# rmtfs and qrtr-tools: need arm64 binaries from Ubuntu Ports
echo ""
echo "  Downloading arm64 binaries from ports.ubuntu.com..."
PORTS="http://ports.ubuntu.com/ubuntu-ports/pool/main"
UNIVERSE="http://ports.ubuntu.com/ubuntu-ports/pool/universe"

# Check if already downloaded
for pkg_name in rmtfs qrtr-tools libqrtr-glib0; do
    existing=$(ls "$PKGDIR/${pkg_name}"_*arm64*.deb 2>/dev/null | head -1)
    if [ -n "$existing" ]; then
        echo "  $pkg_name already downloaded"
        continue
    fi
    # Find the package URL from Ubuntu Ports
    case "$pkg_name" in
        rmtfs)
            wget -q --show-progress -P "$PKGDIR" \
                "${UNIVERSE}/r/rmtfs/rmtfs_1.0-3_arm64.deb" 2>&1 || \
            wget -q --show-progress -P "$PKGDIR" \
                "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/pool/universe/r/rmtfs/rmtfs_1.0-3_arm64.deb" 2>&1 || \
                echo "  WARNING: could not download rmtfs arm64"
            ;;
        qrtr-tools)
            wget -q --show-progress -P "$PKGDIR" \
                "${PORTS}/q/qrtr/qrtr-tools_1.0-2ubuntu3_arm64.deb" 2>&1 || \
            wget -q --show-progress -P "$PKGDIR" \
                "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/pool/main/q/qrtr/qrtr-tools_1.0-2ubuntu3_arm64.deb" 2>&1 || \
                echo "  WARNING: could not download qrtr-tools arm64"
            ;;
        libqrtr-glib0)
            wget -q --show-progress -P "$PKGDIR" \
                "${PORTS}/q/qrtr-glib/libqrtr-glib0_1.2.2-1ubuntu4_arm64.deb" 2>&1 || \
                echo "  WARNING: could not download libqrtr-glib0 arm64"
            ;;
    esac
done

# Extract arm64 debs into rootfs
for deb in "$PKGDIR"/rmtfs_*arm64*.deb "$PKGDIR"/qrtr-tools_*arm64*.deb "$PKGDIR"/libqrtr-glib0_*arm64*.deb; do
    [ -f "$deb" ] || continue
    echo "  Extracting $(basename "$deb") → rootfs"
    dpkg-deb -x "$deb" "$MNT"
done

# Enable rmtfs service (enable by creating symlink)
if [ -f "$MNT/lib/systemd/system/rmtfs.service" ]; then
    mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
    ln -sf /lib/systemd/system/rmtfs.service \
        "$MNT/etc/systemd/system/multi-user.target.wants/rmtfs.service" 2>/dev/null || true
    echo "  rmtfs.service enabled"
fi

echo ""
echo "  Final check:"
echo "  WCN3990: $(ls "$MNT/usr/lib/firmware/ath10k/WCN3990/hw1.0/" 2>/dev/null | wc -l) files"
echo "  rmtfs:   $(ls "$MNT/usr/bin/rmtfs" 2>/dev/null || echo 'not found')"
echo "  qrtr-ns: $(ls "$MNT/usr/bin/qrtr-ns" 2>/dev/null || echo 'not found')"
umount "$MNT"

# ── Step 3: Update DTB in output/ and rebuild boot image ──────
echo ""
echo "=== [3/3] Updating DTB and rebuilding boot image ==="
KERNEL_DTB="$REAL_HOME/razorphone2linux/kernel/linux/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb"
OUTPUT="$REAL_HOME/razorphone2linux/output"

cp -v "$KERNEL_DTB" "$OUTPUT/sdm845-razer-aura.dtb"
echo "  DTB updated in output/ ($(ls -lh "$OUTPUT/sdm845-razer-aura.dtb" | awk '{print $5, $6, $7, $8}'))"

bash "$WIN_DIR/scripts/04-make-observable-boot.sh"

echo ""
echo "=== All done! Ready to flash: ==="
ls -lh "$OUTPUT/boot-observable.img" "$OUTPUT/rootfs-sparse.img" 2>/dev/null
echo ""
echo "Next: run verify-and-resparse.sh to rebuild rootfs-sparse.img"
