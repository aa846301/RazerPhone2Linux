#!/bin/bash
# extract-fw-from-rom.sh
# Extract Qualcomm firmware from ROM zip (dsp.img + vendor.img)
# and inject into existing rootfs-noble.img
set -euo pipefail

ZIP=/mnt/c/repo/razorphone2linux/aura-p-release-3201-user-full.zip
# Use SUDO_USER to get the real user's home dir when running under sudo
REAL_HOME=$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)
# Use persistent dir (not /tmp which is wiped per-session)
EXTRACT="$REAL_HOME/razorphone2linux/fw-extract-tmp/rom"
BASE="$EXTRACT/aura-p-release-3201-user-full/aura-p-release-3201"
FWDIR="$REAL_HOME/razorphone2linux/fw-extract-tmp/out"
ROOTFS="$REAL_HOME/razorphone2linux/rootfs/rootfs-noble.img"
WIN_OUTPUT=/mnt/c/repo/razorphone2linux/output

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: run as root (sudo)"
    exit 1
fi

# ── Step 1: Extract partition images from zip ──────────────────
echo "=== [1/5] Extracting partitions from ROM zip ==="
mkdir -p "$EXTRACT" "$FWDIR"

# Only re-extract if not already present
for part in dsp vendor modem; do
    dst="$BASE/${part}.img"
    if [ -f "$dst" ]; then
        echo "  ${part}.img already extracted, skipping"
    else
        echo "  Extracting ${part}.img..."
        unzip -o "$ZIP" \
            "aura-p-release-3201-user-full/aura-p-release-3201/${part}.img" \
            -d "$EXTRACT"
    fi
done
ls -lh "$BASE/dsp.img" "$BASE/vendor.img" "$BASE/modem.img"

# ── Step 2: Convert sparse → raw (skip if already done) ──────
echo ""
echo "=== [2/5] Converting sparse images to raw ==="
mkdir -p "$FWDIR"

is_sparse() {
    local magic
    magic=$(xxd -l 4 -p "$1" 2>/dev/null)
    [ "$magic" = "3aff26ed" ]
}

for img in dsp vendor modem; do
    src="$BASE/${img}.img"
    dst="$FWDIR/${img}-raw.img"
    if [ -f "$dst" ]; then
        echo "  ${img}-raw.img already exists ($(du -h "$dst" | cut -f1)), skipping"
        continue
    fi
    if is_sparse "$src"; then
        echo "  $img.img is sparse → converting..."
        simg2img "$src" "$dst"
    else
        echo "  $img.img is raw → copying..."
        cp "$src" "$dst"
    fi
    echo "  $(ls -lh "$dst" | awk '{print $5, $9}')"
done

# ── Step 3: Mount and extract firmware ────────────────────────
echo ""
echo "=== [3/5] Mounting partitions ==="
DSP_MNT="$FWDIR/dsp-mnt"
VENDOR_MNT="$FWDIR/vendor-mnt"
MODEM_MNT="$FWDIR/modem-mnt"
mkdir -p "$DSP_MNT" "$VENDOR_MNT" "$MODEM_MNT"

cleanup() {
    umount "$DSP_MNT" 2>/dev/null || true
    umount "$VENDOR_MNT" 2>/dev/null || true
    umount "$MODEM_MNT" 2>/dev/null || true
    umount "$FWDIR/rootfs-mnt" 2>/dev/null || true
}
trap cleanup EXIT

mountpoint -q "$DSP_MNT"    || mount -o ro,loop "$FWDIR/dsp-raw.img"    "$DSP_MNT"
mountpoint -q "$VENDOR_MNT" || mount -o ro,loop "$FWDIR/vendor-raw.img" "$VENDOR_MNT"
# modem.img is typically VFAT containing .mbn blobs
mountpoint -q "$MODEM_MNT"  || mount -o ro,loop "$FWDIR/modem-raw.img"  "$MODEM_MNT" || \
    mount -o ro,loop,uid=0,gid=0 "$FWDIR/modem-raw.img" "$MODEM_MNT" || \
    echo "  WARNING: could not mount modem partition"
echo "  Partitions mounted"

echo "  Modem partition .mbn files:"
find "$MODEM_MNT" -maxdepth 1 -name "*.mbn" 2>/dev/null | head -20
echo "  vendor/firmware/ contents:"
ls "$VENDOR_MNT/firmware/" 2>/dev/null | head -20
echo "  Searching vendor for a630/WCN3990:"
find "$VENDOR_MNT" -name "a630_zap.mbn" -o -name "firmware-5.bin" 2>/dev/null | head -10

# ── Step 4: Mount rootfs and inject firmware ──────────────────
echo ""
echo "=== [4/5] Injecting firmware into rootfs ==="
ROOTFS_MNT="$FWDIR/rootfs-mnt"
mkdir -p "$ROOTFS_MNT"
mount "$ROOTFS" "$ROOTFS_MNT"

QCOM_DEST="$ROOTFS_MNT/usr/lib/firmware/qcom/sdm845/Razer/aura"
ATH10K_DEST="$ROOTFS_MNT/usr/lib/firmware/ath10k/WCN3990/hw1.0"
mkdir -p "$QCOM_DEST" "$ATH10K_DEST"

# adsp/cdsp: split format in modem partition (image/adsp.mdt + adsp.b00..bXX)
# mainline qcom_mdt_load(): expects <name>.mbn (or .mdt), then loads .bXX alongside
for fw in adsp cdsp; do
    mdt_src="$MODEM_MNT/image/${fw}.mdt"
    if [ -f "$mdt_src" ]; then
        # Copy .mdt renamed as .mbn (mainline firmware-name uses .mbn extension)
        cp -v "$mdt_src" "$QCOM_DEST/${fw}.mbn"
        # Copy all segment files alongside
        for seg in "$MODEM_MNT/image/${fw}".b[0-9]*; do
            [ -f "$seg" ] && cp -v "$seg" "$QCOM_DEST/"
        done
    else
        echo "  WARNING: ${fw}.mdt not found in modem/image/"
    fi
done

# a630_zap: split format in vendor/firmware/ (a630_zap.mdt + .b00..b02)
# Also copy a630_gmu.bin and a630_sqe.fw (required by Adreno 630 GMU)
A630_SRC="$VENDOR_MNT/firmware"
for f in a630_zap.mdt a630_zap.b00 a630_zap.b01 a630_zap.b02 \
          a630_gmu.bin a630_sqe.fw; do
    if [ -f "$A630_SRC/$f" ]; then
        dest_name="$f"
        # Rename .mdt → .mbn for the main zap file
        [ "$f" = "a630_zap.mdt" ] && dest_name="a630_zap.mbn"
        cp -v "$A630_SRC/$f" "$QCOM_DEST/$dest_name"
    else
        echo "  WARNING: $f not found in vendor/firmware/"
    fi
done

# venus.mbn (video codec) - may not be present in this ROM
for fw in venus.mbn venus.mdt; do
    src=$(find "$VENDOR_MNT" -name "$fw" 2>/dev/null | head -1)
    [ -n "$src" ] && cp -v "$src" "$QCOM_DEST/venus.mbn" && break || true
done

# WCN3990 ath10k WiFi firmware - look in vendor/firmware/wlan/
ATH10K_SRC=$(find "$VENDOR_MNT" -path "*/ath10k/WCN3990/hw1.0" -type d 2>/dev/null | head -1)
if [ -n "$ATH10K_SRC" ]; then
    cp -rv "$ATH10K_SRC/"* "$ATH10K_DEST/"
    echo "  Copied ath10k WCN3990 firmware from $ATH10K_SRC"
else
    # Check vendor/firmware/wlan/
    WLAN_DIR="$VENDOR_MNT/firmware/wlan"
    if [ -d "$WLAN_DIR" ]; then
        echo "  vendor/firmware/wlan contents:"
        find "$WLAN_DIR" -maxdepth 3 | head -20
        # Copy any wcn3990/qca firmware files found
        find "$WLAN_DIR" -name "*.bin" -o -name "*.bdf" 2>/dev/null | while read -r f; do
            cp -v "$f" "$ATH10K_DEST/" || true
        done
    fi
    echo "  NOTE: WCN3990 firmware may need to come from linux-firmware package"
    echo "  After boot: sudo apt install linux-firmware"
fi

umount "$ROOTFS_MNT"
trap - EXIT
cleanup

echo ""
echo "=== [5/5] Summary: firmware injected ==="
echo "Destination: $QCOM_DEST"
ls -lh "$QCOM_DEST" 2>/dev/null || echo "(check above for errors)"
echo "ATH10K: $ATH10K_DEST"
ls -lh "$ATH10K_DEST" 2>/dev/null || echo "(check above)"

echo ""
echo "Next: sudo bash /mnt/c/repo/razorphone2linux/wsl-scripts/verify-and-resparse.sh"
