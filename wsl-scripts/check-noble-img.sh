#!/bin/bash
# Check rootfs-noble.img for all key customizations
RAW="/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img"
MNT="/home/dinochang/rootfs-noble-mnt"

if [ ! -f "$RAW" ]; then
    echo "ERROR: $RAW not found"
    exit 1
fi
echo "Image: $(ls -lh $RAW)"

umount "$MNT" 2>/dev/null || true
mkdir -p "$MNT"
mount -o loop,ro "$RAW" "$MNT" || { echo "ERROR: mount failed"; exit 1; }
echo "mount: OK"
echo ""

echo "--- usb-gadget-setup.sh ---"
head -5 "$MNT/usr/local/bin/usb-gadget-setup.sh" 2>/dev/null || echo "NOT_FOUND"
echo ""

echo "--- usb-gadget.service ---"
cat "$MNT/etc/systemd/system/usb-gadget.service" 2>/dev/null || echo "NOT_FOUND"
echo ""

echo "--- serial-getty@ttyGS0.service ---"
cat "$MNT/etc/systemd/system/serial-getty@ttyGS0.service" 2>/dev/null || echo "NOT_FOUND"
echo ""

echo "--- after-usb-gadget.conf ---"
cat "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf" 2>/dev/null || echo "NOT_FOUND"
echo ""

echo "--- razer-aura.conf ---"
cat "$MNT/etc/modules-load.d/razer-aura.conf" 2>/dev/null || echo "NOT_FOUND"
echo ""

echo "--- multi-user.target.wants ---"
ls "$MNT/etc/systemd/system/multi-user.target.wants/" 2>/dev/null
echo ""

echo "--- kernel modules ---"
ls "$MNT/lib/modules/" 2>/dev/null || echo "NOT_FOUND"
echo ""

umount "$MNT"
echo "DONE"
