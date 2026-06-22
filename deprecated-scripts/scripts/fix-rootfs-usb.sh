#!/bin/bash
# fix-rootfs-usb.sh
# Mount rootfs-sparse.img, add USB gadget configfs setup service, rebuild sparse.
# Run in WSL as: sudo bash /mnt/c/repo/razorphone2linux/scripts/fix-rootfs-usb.sh

set -e

WINDOWS_REPO="/mnt/c/repo/razorphone2linux"
SPARSE_IN="$WINDOWS_REPO/output/rootfs-sparse.img"
RAW_IMG="/tmp/rootfs-fix.img"
MNT="/tmp/rootfs-mnt"
SPARSE_OUT="$WINDOWS_REPO/output/rootfs-sparse.img"

# -------------------------------------------------------
echo "[1/5] Converting sparse → raw ext4..."
# -------------------------------------------------------
if ! command -v simg2img &>/dev/null; then
    echo "Installing android-tools-fsutils..."
    apt-get install -y android-tools-fsutils 2>/dev/null || \
    apt-get install -y simg2img 2>/dev/null || \
    (apt-get install -y git build-essential && \
     git clone --depth=1 https://github.com/anestisb/android-simg2img /tmp/simg2img-src && \
     make -C /tmp/simg2img-src && \
     cp /tmp/simg2img-src/simg2img /usr/local/bin/ && \
     cp /tmp/simg2img-src/img2simg /usr/local/bin/)
fi

simg2img "$SPARSE_IN" "$RAW_IMG"
echo "  Raw image: $(du -h $RAW_IMG | cut -f1)"

# -------------------------------------------------------
echo "[2/5] Mounting raw ext4..."
# -------------------------------------------------------
mkdir -p "$MNT"
mount -o loop,rw "$RAW_IMG" "$MNT"
echo "  Mounted at $MNT"
df -h "$MNT"

# -------------------------------------------------------
echo "[3/5] Installing USB gadget setup..."
# -------------------------------------------------------

# USB gadget setup script (configfs ACM serial)
cat > "$MNT/usr/local/bin/usb-gadget-setup.sh" << 'GADGET_SCRIPT'
#!/bin/bash
# Setup USB gadget via configfs (ACM serial → ttyGS0)
# Called by usb-gadget.service at boot

LOG_TAG="usb-gadget"

log() { echo "$LOG_TAG: $*" | tee /dev/kmsg 2>/dev/null || true; }

log "Starting USB gadget setup..."

# Wait for UDC (USB Device Controller) to be ready
UDC=""
for i in $(seq 1 20); do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
    [ -n "$UDC" ] && break
    sleep 0.2
done

if [ -z "$UDC" ]; then
    log "ERROR: No UDC found after 4s, aborting"
    exit 1
fi
log "Found UDC: $UDC"

# Unload legacy g_serial if loaded (conflicts with configfs)
if grep -q "^g_serial " /proc/modules 2>/dev/null; then
    log "Unloading legacy g_serial..."
    modprobe -r g_serial 2>/dev/null && log "g_serial unloaded" || log "WARN: failed to unload g_serial"
    sleep 0.3
fi

# Mount configfs if not already mounted
if ! mountpoint -q /sys/kernel/config 2>/dev/null; then
    log "Mounting configfs..."
    mount -t configfs none /sys/kernel/config
fi

GADGET=/sys/kernel/config/usb_gadget/g1

# Tear down existing gadget if present
if [ -d "$GADGET" ]; then
    log "Removing existing gadget..."
    echo "" > "$GADGET/UDC" 2>/dev/null || true
    sleep 0.1
    for f in "$GADGET/configs/c.1/"*; do
        [ -L "$f" ] && rm -f "$f"
    done
    for d in strings configs/c.1/strings configs/c.1 functions/acm.usb0 strings/0x409; do
        rmdir "$GADGET/$d" 2>/dev/null || true
    done
    rmdir "$GADGET" 2>/dev/null || true
fi

# Create gadget
mkdir -p "$GADGET"
echo 0x1d6b > "$GADGET/idVendor"    # Linux Foundation
echo 0x0104 > "$GADGET/idProduct"   # Multifunction Composite Gadget

mkdir -p "$GADGET/strings/0x409"
echo "0409"           > "$GADGET/strings/0x409/languageid"
echo "Razer Phone 2"  > "$GADGET/strings/0x409/product"
echo "razorphone2"    > "$GADGET/strings/0x409/serialnumber"
echo "Linux"          > "$GADGET/strings/0x409/manufacturer"

# ACM serial function (→ ttyGS0 on device, CDC ACM on Windows)
mkdir -p "$GADGET/functions/acm.usb0"

# Configuration
mkdir -p "$GADGET/configs/c.1"
mkdir -p "$GADGET/configs/c.1/strings/0x409"
echo 120 > "$GADGET/configs/c.1/MaxPower"
echo "Serial console" > "$GADGET/configs/c.1/strings/0x409/configuration"

ln -sf "$GADGET/functions/acm.usb0" "$GADGET/configs/c.1/"

# Bind to UDC
echo "$UDC" > "$GADGET/UDC"
log "USB gadget bound to $UDC → /dev/ttyGS0 ready"
GADGET_SCRIPT
chmod +x "$MNT/usr/local/bin/usb-gadget-setup.sh"
echo "  usb-gadget-setup.sh installed"

# usb-gadget.service
cat > "$MNT/etc/systemd/system/usb-gadget.service" << 'USB_SVC'
[Unit]
Description=USB Gadget (ACM Serial Console)
After=local-fs.target
Before=serial-getty@ttyGS0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usb-gadget-setup.sh

[Install]
WantedBy=multi-user.target
USB_SVC
echo "  usb-gadget.service installed"

# Enable usb-gadget.service via symlink
mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/usb-gadget.service \
    "$MNT/etc/systemd/system/multi-user.target.wants/usb-gadget.service"
echo "  usb-gadget.service enabled"

# Update serial-getty@ttyGS0 to depend on usb-gadget.service
mkdir -p "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d"
cat > "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf" << 'DROP_EOF'
[Unit]
After=usb-gadget.service
Requires=usb-gadget.service
DROP_EOF
echo "  serial-getty@ttyGS0 drop-in installed"

# Remove g_serial from /etc/modules (it's built-in =y, this entry is harmless but confusing)
if [ -f "$MNT/etc/modules" ]; then
    sed -i '/^g_serial/d' "$MNT/etc/modules"
    echo "  Removed g_serial from /etc/modules"
fi

# Remove g_serial from modules-load.d (same reason)
if [ -f "$MNT/etc/modules-load.d/razer-aura.conf" ]; then
    sed -i '/^g_serial/d' "$MNT/etc/modules-load.d/razer-aura.conf"
    echo "  Removed g_serial from razer-aura.conf"
fi

echo "[3/5] USB gadget setup done."

# -------------------------------------------------------
echo "[4/5] Unmounting..."
# -------------------------------------------------------
sync
umount "$MNT"
echo "  Unmounted."

# -------------------------------------------------------
echo "[5/5] Converting raw → sparse ext4..."
# -------------------------------------------------------
if ! command -v img2simg &>/dev/null; then
    echo "ERROR: img2simg not found. Install android-tools-fsutils."
    exit 1
fi

# Backup old sparse just in case
cp "$SPARSE_OUT" "${SPARSE_OUT}.bak" && echo "  Backup: ${SPARSE_OUT}.bak"

img2simg "$RAW_IMG" "$SPARSE_OUT"
echo "  Sparse image: $(du -h $SPARSE_OUT | cut -f1)"

rm -f "$RAW_IMG"

echo ""
echo "=== DONE ==="
echo "rootfs-sparse.img updated with USB gadget fix."
echo "Now run in PowerShell:"
echo "  fastboot flash userdata output\\rootfs-sparse.img"
echo "  fastboot reboot"
