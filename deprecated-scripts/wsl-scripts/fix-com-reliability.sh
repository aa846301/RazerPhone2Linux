#!/bin/bash
# Surgical fix for COM (serial-getty@ttyGS0) reliability.
#
# PROBLEM:
#   1. usb-gadget-setup.sh uses "set -euo pipefail" - any configfs error kills
#      the service, which then prevents serial-getty from starting due to
#      "Requires=usb-gadget.service" in the drop-in.
#   2. after-usb-gadget.conf has "Requires=" (hard dependency) instead of
#      "After=" (soft ordering) - so if usb-gadget.service fails, COM dies.
#
# FIX:
#   1. Remove set -euo pipefail from usb-gadget-setup.sh, add || true to UDC bind
#   2. Change Requires= to After= in after-usb-gadget.conf
#   3. Re-sparsify the rootfs-sparse.img
#
# Run as root: wsl -d Ubuntu -u root -- bash /mnt/c/repo/razorphone2linux/wsl-scripts/fix-com-reliability.sh

set -e

WINDOWS_REPO="/mnt/c/repo/razorphone2linux"
SPARSE_IN="$WINDOWS_REPO/output/rootfs-sparse.img"
RAW_IMG="/tmp/rootfs-com-fix.img"
MNT="/tmp/rootfs-com-fix-mnt"
SPARSE_OUT="$WINDOWS_REPO/output/rootfs-sparse.img"

echo "=============================="
echo " COM Reliability Fix"
echo "=============================="

echo ""
echo "[1/5] Converting sparse → raw ext4..."
rm -f "$RAW_IMG"
simg2img "$SPARSE_IN" "$RAW_IMG"
echo "  Raw image: $(du -h $RAW_IMG | cut -f1)"

echo ""
echo "[2/5] Mounting raw ext4 (rw)..."
mkdir -p "$MNT"
umount "$MNT" 2>/dev/null || true
mount -o loop,rw "$RAW_IMG" "$MNT"
echo "  Mounted at $MNT"

echo ""
echo "[3/5] Fixing usb-gadget-setup.sh (removing set -euo pipefail)..."
GADGET_SCRIPT="$MNT/usr/local/bin/usb-gadget-setup.sh"
if [ ! -f "$GADGET_SCRIPT" ]; then
    echo "  ERROR: usb-gadget-setup.sh not found - rootfs may be incomplete"
    umount "$MNT"
    exit 1
fi

echo "  Before:"
head -5 "$GADGET_SCRIPT"

cat > "$GADGET_SCRIPT" << 'GADGET_EOF'
#!/bin/bash
# USB ACM serial gadget setup via ConfigFS
# Resilient: never fails the service even if USB gadget setup encounters errors

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

# Unbind and clean up any previous gadget state
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
echo "Razer"                      > "$GADGET/strings/0x409/manufacturer"
echo "Razer Phone 2 Linux Console" > "$GADGET/strings/0x409/product"
echo "aura-linux"                 > "$GADGET/strings/0x409/serialnumber"
echo "ACM serial console"         > "$GADGET/configs/c.1/strings/0x409/configuration"
echo 120                          > "$GADGET/configs/c.1/MaxPower"

mkdir -p "$GADGET/functions/acm.usb0" 2>/dev/null || { log "ACM function create failed (not compiled in?)"; exit 0; }
ln -sf "$GADGET/functions/acm.usb0" "$GADGET/configs/c.1/acm.usb0" 2>/dev/null || true

# Bind to UDC - use || true so service always succeeds
if echo "$UDC" > "$GADGET/UDC" 2>/dev/null; then
    log "bound ACM serial gadget to $UDC"
else
    log "UDC bind failed (EBUSY or other error) - gadget not active"
fi
GADGET_EOF

chmod +x "$GADGET_SCRIPT"
echo "  Fixed: removed set -euo pipefail, added || true to UDC bind"

echo ""
echo "[4/5] Fixing after-usb-gadget.conf (Requires → After)..."
DROPIN_DIR="$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d"
DROPIN_FILE="$DROPIN_DIR/after-usb-gadget.conf"

if [ -f "$DROPIN_FILE" ]; then
    echo "  Before:"
    cat "$DROPIN_FILE"
    cat > "$DROPIN_FILE" << 'DROPIN_EOF'
[Unit]
# Soft ordering only - serial-getty starts even if usb-gadget.service fails.
# The agetty process will wait for ttyGS0 to appear (Restart=always handles retries).
After=usb-gadget.service
DROPIN_EOF
    echo "  Fixed: changed Requires= to After= (soft ordering only)"
else
    echo "  Drop-in not found - creating it with safe After= only"
    mkdir -p "$DROPIN_DIR"
    cat > "$DROPIN_FILE" << 'DROPIN_EOF'
[Unit]
After=usb-gadget.service
DROPIN_EOF
fi

echo ""
echo "[4b/5] Verifying serial-getty@ttyGS0 is in multi-user.target.wants..."
WANTS_DIR="$MNT/etc/systemd/system/multi-user.target.wants"
GETTY_LINK="$WANTS_DIR/serial-getty@ttyGS0.service"
if [ -L "$GETTY_LINK" ]; then
    echo "  OK: serial-getty@ttyGS0 already enabled"
    ls -la "$GETTY_LINK"
else
    echo "  Enabling serial-getty@ttyGS0..."
    mkdir -p "$WANTS_DIR"
    ln -sf /etc/systemd/system/serial-getty@ttyGS0.service "$GETTY_LINK"
fi

echo ""
echo "[5/5] Unmounting and converting back to sparse..."
umount "$MNT"
rmdir "$MNT" 2>/dev/null || true

if command -v img2simg &>/dev/null; then
    img2simg "$RAW_IMG" "$SPARSE_OUT"
    rm -f "$RAW_IMG"
    echo "  Sparse image: $(du -h $SPARSE_OUT | cut -f1)"
else
    echo "  ERROR: img2simg not found"
    rm -f "$RAW_IMG"
    exit 1
fi

echo ""
echo "=============================="
echo " DONE"
echo "=============================="
echo "Changes:"
echo "  - usb-gadget-setup.sh: resilient (no set -euo pipefail)"
echo "  - after-usb-gadget.conf: Requires= changed to After="
echo ""
echo "Result: serial-getty@ttyGS0 will start regardless of USB gadget state."
echo "        COM port appears on Windows once USB gadget is set up."
echo ""
echo "Flash: fastboot flash userdata output\\rootfs-sparse.img"
