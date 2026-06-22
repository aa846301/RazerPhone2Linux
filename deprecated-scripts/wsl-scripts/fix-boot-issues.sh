#!/bin/bash
# Fix three root causes preventing stable boot on Razer Phone 2:
#   1. VID 0x18d1 (Google) → Windows loads Android ADB driver → no COM port
#      Fix: change to 0x0525:0xa4a7 (Linux Foundation CDC ACM)
#   2. msm module load → conflicts with SimpleDRM → kernel panic → panic=30 reboot
#      Fix: remove msm (and panel-novatek-nt36830) from modules-load.d
#   3. xinit-klipperscreen.service → may have FailureAction=reboot
#      Fix: disable it from multi-user.target.wants
# Then img2simg → Windows NTFS output/rootfs-sparse.img

set -e

NOBLE_IMG="/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img"
MNT="/home/dinochang/rootfs-noble-fix-mnt"
SPARSE_OUT="/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img"

echo "========================================"
echo " Fix boot issues in rootfs-noble.img"
echo "========================================"

if [ ! -f "$NOBLE_IMG" ]; then
    echo "ERROR: $NOBLE_IMG not found"; exit 1
fi
echo "Source: $(ls -lh $NOBLE_IMG)"

echo ""
echo "[1/5] Mounting noble.img (rw)..."
umount "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
mount -o loop,rw "$NOBLE_IMG" "$MNT"
echo "  Mounted OK"

# ─── Fix 1: VID/PID ───────────────────────────────────────────────────────
echo ""
echo "[2/5] Fix 1: Change USB gadget VID/PID 0x18d1→0x0525, 0x4ee7→0xa4a7..."
GADGET_SCRIPT="$MNT/usr/local/bin/usb-gadget-setup.sh"
if [ ! -f "$GADGET_SCRIPT" ]; then
    echo "  ERROR: $GADGET_SCRIPT not found"; umount "$MNT"; exit 1
fi

# In-place sed replacement
sed -i \
    's|echo 0x18d1 > "\$GADGET/idVendor"|echo 0x0525 > "$GADGET/idVendor"|g' \
    "$GADGET_SCRIPT"
sed -i \
    's|echo 0x4ee7 > "\$GADGET/idProduct"|echo 0xa4a7 > "$GADGET/idProduct"|g' \
    "$GADGET_SCRIPT"

# Verify
VID=$(grep idVendor "$GADGET_SCRIPT" | grep -o '0x[0-9a-fA-F]*' | head -1)
PID=$(grep idProduct "$GADGET_SCRIPT" | grep -o '0x[0-9a-fA-F]*' | head -1)
echo "  VID=$VID  PID=$PID"
if [ "$VID" != "0x0525" ] || [ "$PID" != "0xa4a7" ]; then
    echo "  WARNING: sed replacement may have failed, rewriting full script..."
    # Rewrite the whole script with correct VID/PID
    cat > "$GADGET_SCRIPT" << 'GADGET_EOF'
#!/bin/bash
# USB ACM serial gadget setup via ConfigFS
# VID 0x0525 (Linux Foundation) / PID 0xa4a7 (CDC ACM)
# Resilient: never fails the service

log() { echo "usb-gadget: $*" > /dev/kmsg 2>/dev/null || true; }

UDC=""
for _ in $(seq 1 30); do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -n 1 || true)
    [ -n "$UDC" ] && break
    sleep 0.2
done

if [ -z "$UDC" ]; then
    log "no UDC available - skipping gadget setup"
    exit 0
fi

log "UDC found: $UDC"

mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config 2>/dev/null || true

GADGET=/sys/kernel/config/usb_gadget/g1

# Clean up any previous gadget state
if [ -d "$GADGET" ]; then
    echo "" > "$GADGET/UDC" 2>/dev/null || true
    find "$GADGET/configs" -type l -delete 2>/dev/null || true
    find "$GADGET/functions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r fn; do
        rmdir "$fn" 2>/dev/null || true
    done
fi

mkdir -p "$GADGET/strings/0x409" || { log "configfs mkdir failed"; exit 0; }
mkdir -p "$GADGET/configs/c.1/strings/0x409"

# Linux Foundation CDC ACM VID/PID - Windows creates COM port for these
echo 0x0525 > "$GADGET/idVendor"
echo 0xa4a7 > "$GADGET/idProduct"
echo 0x0200 > "$GADGET/bcdUSB"
echo 0x0100 > "$GADGET/bcdDevice"
echo 0x02   > "$GADGET/bDeviceClass"
echo 0x02   > "$GADGET/bDeviceSubClass"
echo 0x01   > "$GADGET/bDeviceProtocol"
echo "Razer"                       > "$GADGET/strings/0x409/manufacturer"
echo "Razer Phone 2 Linux Console" > "$GADGET/strings/0x409/product"
echo "aura-linux"                  > "$GADGET/strings/0x409/serialnumber"
echo "ACM serial console"          > "$GADGET/configs/c.1/strings/0x409/configuration"
echo 120                           > "$GADGET/configs/c.1/MaxPower"

mkdir -p "$GADGET/functions/acm.usb0" 2>/dev/null || { log "ACM function create failed"; exit 0; }
ln -sf "$GADGET/functions/acm.usb0" "$GADGET/configs/c.1/acm.usb0" 2>/dev/null || true

if echo "$UDC" > "$GADGET/UDC" 2>/dev/null; then
    log "bound ACM serial gadget to $UDC"
else
    log "UDC bind failed (EBUSY?) - gadget not active this boot"
fi
GADGET_EOF
    chmod +x "$GADGET_SCRIPT"
    VID=$(grep idVendor "$GADGET_SCRIPT" | grep -o '0x[0-9a-fA-F]*' | head -1)
    PID=$(grep idProduct "$GADGET_SCRIPT" | grep -o '0x[0-9a-fA-F]*' | head -1)
    echo "  Rewritten. VID=$VID  PID=$PID"
fi

# ─── Fix 2: Remove msm + panel driver from modules-load.d ─────────────────
echo ""
echo "[3/5] Fix 2: Remove msm/panel-novatek-nt36830 from modules-load.d..."
MODCONF="$MNT/etc/modules-load.d/razer-aura.conf"
if [ -f "$MODCONF" ]; then
    echo "  Before:"
    cat "$MODCONF" | sed 's/^/    /'
    # Comment out msm and panel-novatek-nt36830 (DRM conflict)
    sed -i \
        -e 's/^msm$/#msm  # disabled: conflicts with SimpleDRM/' \
        -e 's/^panel-novatek-nt36830$/#panel-novatek-nt36830  # disabled with msm/' \
        "$MODCONF"
    echo "  After:"
    cat "$MODCONF" | sed 's/^/    /'
else
    echo "  WARNING: $MODCONF not found"
fi

# ─── Fix 3: Disable xinit-klipperscreen.service ───────────────────────────
echo ""
echo "[4/5] Fix 3: Disable xinit-klipperscreen.service..."
WANTS_DIR="$MNT/etc/systemd/system/multi-user.target.wants"
KLIPPER_LINK="$WANTS_DIR/xinit-klipperscreen.service"
if [ -L "$KLIPPER_LINK" ] || [ -f "$KLIPPER_LINK" ]; then
    rm -f "$KLIPPER_LINK"
    echo "  Removed symlink: $KLIPPER_LINK"
else
    echo "  Not found (already disabled or doesn't exist)"
fi

# Also mask it to prevent any re-enable
mkdir -p "$MNT/etc/systemd/system"
ln -sf /dev/null "$MNT/etc/systemd/system/xinit-klipperscreen.service" 2>/dev/null || true
echo "  Masked xinit-klipperscreen.service -> /dev/null"

# ─── Verify state ─────────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
echo "--- usb-gadget-setup.sh VID/PID ---"
grep 'idVendor\|idProduct' "$GADGET_SCRIPT" | head -4
echo "--- razer-aura.conf ---"
cat "$MODCONF" 2>/dev/null || echo "(not found)"
echo "--- multi-user.target.wants ---"
ls "$WANTS_DIR/" 2>/dev/null | sed 's/^/  /'

# ─── Rebuild sparse ────────────────────────────────────────────────────────
echo ""
echo "[5/5] Unmounting and creating sparse image..."
umount "$MNT"
echo "  Running img2simg..."
img2simg "$NOBLE_IMG" "$SPARSE_OUT"
echo "  Sparse: $(ls -lh $SPARSE_OUT)"

echo ""
echo "========================================"
echo " DONE"
echo "========================================"
echo ""
echo "Flash commands (userdata only, boot.img unchanged):"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
echo ""
echo "After reboot, Windows should show 'COM3' or 'USB Serial Device'"
echo "instead of 'Android Composite ADB Interface'."
