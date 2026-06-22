#!/bin/bash
# USB composite gadget: ACM serial console + NCM ethernet.
# This script is copied into the rootfs by scripts/03-build-rootfs.sh.

set -u

log() { echo "usb-gadget: $*" > /dev/kmsg 2>/dev/null || true; }

modprobe libcomposite 2>/dev/null || true

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

mkdir -p "$GADGET/strings/0x409" "$GADGET/configs/c.1/strings/0x409" || {
    log "configfs mkdir failed"
    exit 0
}

echo 0x0525 > "$GADGET/idVendor"
echo 0xa4a7 > "$GADGET/idProduct"
echo 0x0200 > "$GADGET/bcdUSB"
echo 0x0100 > "$GADGET/bcdDevice"
echo 0xEF > "$GADGET/bDeviceClass"
echo 0x02 > "$GADGET/bDeviceSubClass"
echo 0x01 > "$GADGET/bDeviceProtocol"
echo "Razer" > "$GADGET/strings/0x409/manufacturer"
echo "Razer Phone 2 Linux" > "$GADGET/strings/0x409/product"
echo "aura-linux" > "$GADGET/strings/0x409/serialnumber"
echo "ACM serial + NCM ethernet" > "$GADGET/configs/c.1/strings/0x409/configuration"
echo 250 > "$GADGET/configs/c.1/MaxPower"

mkdir -p "$GADGET/functions/acm.usb0" 2>/dev/null || {
    log "ACM function create failed"
    exit 0
}
ln -sf "$GADGET/functions/acm.usb0" "$GADGET/configs/c.1/acm.usb0" 2>/dev/null || true

if mkdir -p "$GADGET/functions/ncm.usb0" 2>/dev/null; then
    echo "02:de:ad:be:ef:02" > "$GADGET/functions/ncm.usb0/host_addr" 2>/dev/null || true
    echo "02:de:ad:be:ef:01" > "$GADGET/functions/ncm.usb0/dev_addr" 2>/dev/null || true
    ln -sf "$GADGET/functions/ncm.usb0" "$GADGET/configs/c.1/ncm.usb0" 2>/dev/null || true
    log "NCM ethernet function added"
else
    log "NCM function create failed"
fi

if [ -d /sys/bus/gadget/drivers/g_serial ]; then
    ls /sys/bus/gadget/drivers/g_serial/ 2>/dev/null \
        | grep -vE '^(bind|unbind|module|uevent|new_id|remove_id)$' \
        | while read -r dev; do
            echo "$dev" > /sys/bus/gadget/drivers/g_serial/unbind 2>/dev/null && \
                log "unbound g_serial from $dev" || true
        done
    sleep 0.1
fi

if echo "$UDC" > "$GADGET/UDC" 2>/dev/null; then
    log "bound composite gadget (ACM+NCM) to $UDC"
    sleep 1
    if ip link show usb0 >/dev/null 2>&1; then
        ip addr flush dev usb0 2>/dev/null || true
        ip addr add 192.168.137.133/24 dev usb0 2>/dev/null || true
        ip link set usb0 up 2>/dev/null || true
        log "usb0 configured: 192.168.137.133/24"
    else
        log "usb0 not available after bind"
    fi
else
    log "UDC bind failed - gadget not active this boot"
fi

exit 0
