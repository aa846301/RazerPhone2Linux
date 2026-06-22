#!/bin/bash
# Verify rootfs-sparse.img, and regenerate from noble.img if corrupted.
# Also checks noble.img has correct patches applied.

set -e

NOBLE_IMG="/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img"
SPARSE_OUT="/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img"
MNT="/home/dinochang/rootfs-noble-verify-mnt"

echo "=== Sparse verification & regeneration ==="
echo ""

# Step 1: Check noble.img state
echo "[1/4] Checking noble.img state..."
if [ ! -f "$NOBLE_IMG" ]; then
    echo "ERROR: noble.img not found"; exit 1
fi
echo "  noble.img: $(ls -lh $NOBLE_IMG | awk '{print $5, $6, $7, $8}')"

umount "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
mount -o loop,rw "$NOBLE_IMG" "$MNT"
echo "  Mounted OK"

# Check VID/PID
VID=$(grep 'idVendor' "$MNT/usr/local/bin/usb-gadget-setup.sh" 2>/dev/null | grep -o '0x[0-9a-fA-F]*' | head -1 || echo "MISSING")
PID=$(grep 'idProduct' "$MNT/usr/local/bin/usb-gadget-setup.sh" 2>/dev/null | grep -o '0x[0-9a-fA-F]*' | head -1 || echo "MISSING")
MSM=$(grep '^msm' "$MNT/etc/modules-load.d/razer-aura.conf" 2>/dev/null || echo "COMMENTED_OUT")
KLIPPER_WANTS="$MNT/etc/systemd/system/multi-user.target.wants/xinit-klipperscreen.service"
KLIPPER_MASKED="$MNT/etc/systemd/system/xinit-klipperscreen.service"
PIPEFAIL=$(grep 'set -euo pipefail' "$MNT/usr/local/bin/usb-gadget-setup.sh" 2>/dev/null || echo "REMOVED")
REQUIRES=$(grep 'Requires=' "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf" 2>/dev/null || echo "REMOVED")

echo ""
echo "  Noble.img patch status:"
echo "    VID=$VID (want 0x0525)"
echo "    PID=$PID (want 0xa4a7)"
echo "    set -euo pipefail: $PIPEFAIL (want REMOVED)"
echo "    Requires= in drop-in: $REQUIRES (want REMOVED)"
echo "    msm module: '$MSM' (want COMMENTED_OUT)"
echo "    klipper in wants: $(ls $KLIPPER_WANTS 2>/dev/null || echo NOT_PRESENT) (want NOT_PRESENT)"
echo "    klipper masked: $(ls -la $KLIPPER_MASKED 2>/dev/null | grep -o 'dev/null' || echo 'NOT_MASKED')"

NEED_PATCH=0
[ "$VID" != "0x0525" ] && NEED_PATCH=1 && echo "  -> VID needs fix"
[ "$PID" != "0xa4a7" ] && NEED_PATCH=1 && echo "  -> PID needs fix"
[ "$PIPEFAIL" != "REMOVED" ] && NEED_PATCH=1 && echo "  -> set -euo pipefail needs removal"
[ "$REQUIRES" != "REMOVED" ] && NEED_PATCH=1 && echo "  -> Requires= needs removal"
[ "$MSM" != "COMMENTED_OUT" ] && NEED_PATCH=1 && echo "  -> msm needs commenting out"
[ -e "$KLIPPER_WANTS" ] && NEED_PATCH=1 && echo "  -> xinit-klipperscreen still in wants"

if [ "$NEED_PATCH" -eq 1 ]; then
    echo ""
    echo "  Applying missing patches to noble.img..."

    GADGET="$MNT/usr/local/bin/usb-gadget-setup.sh"
    cat > "$GADGET" << 'GADGET_EOF'
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

if [ -d "$GADGET" ]; then
    echo "" > "$GADGET/UDC" 2>/dev/null || true
    find "$GADGET/configs" -type l -delete 2>/dev/null || true
    find "$GADGET/functions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r fn; do
        rmdir "$fn" 2>/dev/null || true
    done
fi

mkdir -p "$GADGET/strings/0x409" || { log "configfs mkdir failed"; exit 0; }
mkdir -p "$GADGET/configs/c.1/strings/0x409"

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
    log "UDC bind failed - gadget not active this boot"
fi
GADGET_EOF
    chmod +x "$GADGET"

    DROPIN="$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf"
    mkdir -p "$(dirname $DROPIN)"
    printf '[Unit]\nAfter=usb-gadget.service\n' > "$DROPIN"

    sed -i \
        -e 's/^msm$/#msm  # disabled: conflicts with SimpleDRM/' \
        -e 's/^panel-novatek-nt36830$/#panel-novatek-nt36830  # disabled with msm/' \
        "$MNT/etc/modules-load.d/razer-aura.conf"

    rm -f "$KLIPPER_WANTS"
    ln -sf /dev/null "$KLIPPER_MASKED" 2>/dev/null || true

    echo "  Patches applied."
fi

echo ""
echo "[2/4] Flushing filesystem and unmounting noble.img..."
sync
umount "$MNT"
echo "  Unmounted OK"

# Step 3: Run fsck to ensure clean ext4
echo ""
echo "[3/4] Running e2fsck on noble.img..."
e2fsck -fp "$NOBLE_IMG" 2>&1 || true
echo "  e2fsck done"

# Step 4: Regenerate sparse
echo ""
echo "[4/4] Regenerating sparse image..."
img2simg "$NOBLE_IMG" "$SPARSE_OUT"
SIZE=$(ls -lh "$SPARSE_OUT" | awk '{print $5}')
echo "  Sparse: $SIZE -> $SPARSE_OUT"

# Quick sanity check: read first 4 bytes (sparse magic = 0x3aff26ed)
MAGIC=$(hexdump -n 4 -e '1/4 "%08x"' "$SPARSE_OUT" 2>/dev/null || echo "error")
echo "  Sparse magic: $MAGIC (expect ed26ff3a)"

echo ""
echo "=== DONE ==="
echo "Flash commands:"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
