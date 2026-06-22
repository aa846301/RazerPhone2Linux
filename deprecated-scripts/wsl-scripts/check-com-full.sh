#!/bin/bash
# Full diagnosis of usb-gadget-setup.sh and COM serial state
SPARSE=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img
TMP_RAW=/tmp/chk-com.img
MNT=/tmp/chk-com-mnt
mkdir -p "$MNT"
umount "$MNT" 2>/dev/null || true
rm -f "$TMP_RAW"

simg2img "$SPARSE" "$TMP_RAW"
mount -o loop,ro "$TMP_RAW" "$MNT"

echo "=== FULL usb-gadget-setup.sh ==="
cat "$MNT/usr/local/bin/usb-gadget-setup.sh"

echo ""
echo "=== wpa_supplicant.conf check ==="
ls -la "$MNT/etc/wpa_supplicant/" 2>/dev/null || echo NOT_FOUND

echo ""
echo "=== /etc/modules-load.d/ ==="
ls "$MNT/etc/modules-load.d/" 2>/dev/null || echo EMPTY
cat "$MNT/etc/modules-load.d/"*.conf 2>/dev/null || echo "no conf files"

echo ""
echo "=== kernel commandline in /etc/ or /boot/ ==="
cat "$MNT/etc/kernel/cmdline" 2>/dev/null || echo NOT_FOUND

echo ""
echo "=== Network interfaces ==="
cat "$MNT/etc/netplan/"*.yaml 2>/dev/null | head -30 || echo NO_NETPLAN

umount "$MNT"
rm -f "$TMP_RAW"
echo DONE
