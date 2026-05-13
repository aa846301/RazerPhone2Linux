#!/bin/bash
# Fix COM reliability in rootfs-noble.img and produce new rootfs-sparse.img
# Changes:
#   1. usb-gadget-setup.sh: remove set -euo pipefail, add || true guards
#   2. after-usb-gadget.conf: Requires= -> After= (soft dependency only)
# Then img2simg -> copy to Windows NTFS

set -e

NOBLE_IMG="/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img"
MNT="/home/dinochang/rootfs-noble-fix-mnt"
SPARSE_OUT="/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img"

echo "=============================="
echo " Fix rootfs-noble.img for COM"
echo "=============================="

if [ ! -f "$NOBLE_IMG" ]; then
    echo "ERROR: $NOBLE_IMG not found"
    exit 1
fi
echo "Source: $(ls -lh $NOBLE_IMG)"

echo ""
echo "[1/4] Mounting noble.img (rw)..."
umount "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
mount -o loop,rw "$NOBLE_IMG" "$MNT"
echo "  Mounted OK"

echo ""
echo "[2/4] Fixing usb-gadget-setup.sh..."
GADGET_SCRIPT="$MNT/usr/local/bin/usb-gadget-setup.sh"

cat > "$GADGET_SCRIPT" << 'GADGET_EOF'
#!/bin/bash
# USB ACM serial gadget setup via ConfigFS
# Resilient: never fails the service even if gadget setup encounters errors

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

echo 0x18d1 > "$GADGET/idVendor"
echo 0x4ee7 > "$GADGET/idProduct"
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

# Bind - always succeed regardless of result
if echo "$UDC" > "$GADGET/UDC" 2>/dev/null; then
    log "bound ACM serial gadget to $UDC"
else
    log "UDC bind failed (EBUSY?) - gadget not active this boot"
fi
GADGET_EOF

chmod +x "$GADGET_SCRIPT"
echo "  Fixed: removed set -euo pipefail, added resilience"
echo "  New head:"
head -4 "$GADGET_SCRIPT"

echo ""
echo "[3/4] Fixing after-usb-gadget.conf (Requires -> After)..."
DROPIN="$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf"

if [ -f "$DROPIN" ]; then
    echo "  Before: $(cat $DROPIN | tr '\n' ' ')"
    cat > "$DROPIN" << 'DROPIN_EOF'
[Unit]
After=usb-gadget.service
DROPIN_EOF
    echo "  After:  $(cat $DROPIN | tr '\n' ' ')"
else
    echo "  Drop-in not found, creating..."
    mkdir -p "$(dirname $DROPIN)"
    echo -e '[Unit]\nAfter=usb-gadget.service' > "$DROPIN"
fi

echo ""
echo "[4/4] Unmounting and creating sparse image..."
umount "$MNT"

echo "  Running img2simg..."
img2simg "$NOBLE_IMG" "$SPARSE_OUT"
echo "  Sparse: $(ls -lh $SPARSE_OUT)"

echo ""
echo "=============================="
echo " DONE"
echo "=============================="
echo ""
echo "Flash commands:"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
