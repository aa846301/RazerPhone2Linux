#!/bin/bash
# finalize-rootfs.sh
# 1. Confirm WCN3990 firmware path (lib vs usr/lib)
# 2. Download + inject arm64 rmtfs, qrtr-tools
# 3. Update DTB in output/ and rebuild boot image
# 4. verify-and-resparse
set -euo pipefail

REAL_HOME=$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)
ROOTFS="$REAL_HOME/razorphone2linux/rootfs/rootfs-noble.img"
MNT="$REAL_HOME/razorphone2linux/fw-extract-tmp/mnt"
PKGDIR="$REAL_HOME/razorphone2linux/fw-extract-tmp/debs"
WIN_DIR=/mnt/c/repo/razorphone2linux
OUTPUT="$REAL_HOME/razorphone2linux/output"
KERNEL_DTB="$REAL_HOME/razorphone2linux/kernel/linux/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dtb"

mkdir -p "$MNT" "$PKGDIR"

# ── Step 1: Fix WCN3990 firmware symlink if needed ────────────
echo "=== [1/4] Checking WCN3990 firmware location ==="
trap "umount '$MNT' 2>/dev/null || true" EXIT
mount "$ROOTFS" "$MNT"

LIB_WCN="$MNT/lib/firmware/ath10k/WCN3990/hw1.0"
USR_WCN="$MNT/usr/lib/firmware/ath10k/WCN3990/hw1.0"

if [ -d "$LIB_WCN" ] && [ "$(ls "$LIB_WCN" 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "  WCN3990 in /lib/firmware/ ✓ ($(ls "$LIB_WCN" | wc -l) files)"
    # Ensure /usr/lib/firmware is a symlink or also has the files
    if [ ! -e "$USR_WCN" ]; then
        mkdir -p "$(dirname "$USR_WCN")"
        # Create a symlink usr/lib/firmware/ath10k → /lib/firmware/ath10k
        # Actually mainline kernel looks in /lib/firmware primarily, so this is fine
        echo "  Kernel firmware search path includes /lib/firmware - OK"
    fi
elif [ -d "$USR_WCN" ] && [ "$(ls "$USR_WCN" 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "  WCN3990 in /usr/lib/firmware/ ✓"
else
    echo "  WARNING: WCN3990 firmware not found in either location!"
fi

umount "$MNT"
trap - EXIT

# ── Step 2: Get arm64 rmtfs + qrtr-tools ──────────────────────
echo ""
echo "=== [2/4] Getting arm64 rmtfs + qrtr-tools ==="

# Use apt to find current version then build the ports URL
get_arm64_pkg() {
    local pkg="$1"
    local existing
    existing=$(ls "$PKGDIR/${pkg}_"*arm64*.deb 2>/dev/null | head -1)
    if [ -n "$existing" ]; then
        echo "  $pkg arm64 already downloaded: $(basename "$existing")"
        return 0
    fi

    # Get version from apt cache
    local ver
    ver=$(apt-cache show "$pkg" 2>/dev/null | grep '^Version:' | head -1 | awk '{print $2}')
    if [ -z "$ver" ]; then
        echo "  WARNING: $pkg not found in apt cache"
        return 1
    fi
    echo "  $pkg version: $ver"

    # Build Ubuntu Ports URL
    local src_pkg
    src_pkg=$(apt-cache show "$pkg" 2>/dev/null | grep '^Source:' | head -1 | awk '{print $2}')
    [ -z "$src_pkg" ] && src_pkg="$pkg"
    local first="${src_pkg:0:1}"
    local sub
    if [[ "$src_pkg" == lib* ]]; then
        sub="${src_pkg:0:4}"
    else
        sub="$first"
    fi

    for mirror in \
        "http://ports.ubuntu.com/ubuntu-ports/pool/main/$sub/$src_pkg/${pkg}_${ver}_arm64.deb" \
        "http://ports.ubuntu.com/ubuntu-ports/pool/universe/$sub/$src_pkg/${pkg}_${ver}_arm64.deb" \
        "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/pool/main/$sub/$src_pkg/${pkg}_${ver}_arm64.deb" \
        "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/pool/universe/$sub/$src_pkg/${pkg}_${ver}_arm64.deb"; do
        if wget -q --spider "$mirror" 2>/dev/null; then
            echo "  Downloading from: $mirror"
            wget -q -P "$PKGDIR" "$mirror" && return 0
        fi
    done
    echo "  WARNING: could not download $pkg arm64 - will install after first boot via apt"
    return 0
}

get_arm64_pkg rmtfs        || true
get_arm64_pkg qrtr-tools   || true
get_arm64_pkg libqrtr-glib0 || true

# Inject arm64 debs into rootfs
mount "$ROOTFS" "$MNT"
trap "umount '$MNT' 2>/dev/null || true" EXIT

for deb in "$PKGDIR"/*arm64*.deb; do
    [ -f "$deb" ] || continue
    echo "  Extracting $(basename "$deb") → rootfs"
    dpkg-deb -x "$deb" "$MNT"
done

# Enable rmtfs.service
if [ -f "$MNT/lib/systemd/system/rmtfs.service" ]; then
    mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
    ln -sf /lib/systemd/system/rmtfs.service \
        "$MNT/etc/systemd/system/multi-user.target.wants/rmtfs.service" 2>/dev/null || true
    echo "  rmtfs.service enabled"
fi

echo "  rmtfs:   $(ls "$MNT/usr/bin/rmtfs" 2>/dev/null || echo 'not found - install after boot: apt install rmtfs')"
echo "  qrtr-ns: $(ls "$MNT/usr/bin/qrtr-ns" 2>/dev/null || echo 'not found - install after boot: apt install qrtr-tools')"
umount "$MNT"
trap - EXIT

# ── Step 3: Update DTB in output/ and rebuild boot image ──────
echo ""
echo "=== [3/4] Updating DTB and rebuilding boot image ==="
cp -v "$KERNEL_DTB" "$OUTPUT/sdm845-razer-aura.dtb"
# Run 04-make-observable-boot.sh as the real user (not root) since it uses $HOME
sudo -u "${SUDO_USER:-$(whoami)}" bash "$WIN_DIR/scripts/04-make-observable-boot.sh"

# ── Step 4: Resparse rootfs ───────────────────────────────────
echo ""
echo "=== [4/4] Rebuilding rootfs sparse image ==="
bash "$WIN_DIR/wsl-scripts/verify-and-resparse.sh"

echo ""
echo "======================================================="
echo " ALL DONE - Ready to flash!"
echo "======================================================="
ls -lh "$OUTPUT/boot-observable.img" "$OUTPUT/rootfs-sparse.img"
echo ""
echo "Flash commands:"
echo "  fastboot flash boot_a   output\\boot-observable.img"
echo "  fastboot flash boot_b   output\\boot-observable.img"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
