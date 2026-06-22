#!/bin/bash
# Check critical USB gadget setup script and COM-breaking issues in sparse image
SPARSE=/mnt/c/repo/razorphone2linux/output/rootfs-sparse.img
TMP_RAW=/tmp/chk-gadget.img
MNT=/tmp/chk-gadget-mnt

mkdir -p "$MNT"
umount "$MNT" 2>/dev/null || true
rm -f "$TMP_RAW"

echo "=== Converting sparse -> raw ==="
simg2img "$SPARSE" "$TMP_RAW"
mount -o loop,ro "$TMP_RAW" "$MNT"

echo ""
echo "=== /usr/local/bin/usb-gadget-setup.sh ==="
if [ -f "$MNT/usr/local/bin/usb-gadget-setup.sh" ]; then
    echo "EXISTS ($(wc -l < "$MNT/usr/local/bin/usb-gadget-setup.sh") lines)"
    head -30 "$MNT/usr/local/bin/usb-gadget-setup.sh"
else
    echo "*** MISSING - This breaks COM! ***"
fi

echo ""
echo "=== after-usb-gadget.conf (the problematic drop-in) ==="
cat "$MNT/etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf" 2>/dev/null || echo "NOT FOUND"

echo ""
echo "=== multi-user.target.wants ==="
ls -la "$MNT/etc/systemd/system/multi-user.target.wants/" 2>/dev/null | grep -v '^total\|^\.'

echo ""
echo "=== getty.target.wants ==="
ls -la "$MNT/etc/systemd/system/getty.target.wants/" 2>/dev/null | grep -v '^total\|^\.'

echo ""
echo "=== Check if ttyGS0 enabled anywhere ==="
grep -r "ttyGS0" "$MNT/etc/systemd/system/" 2>/dev/null | head -20

umount "$MNT"
rm -f "$TMP_RAW"
echo ""
echo "DONE"
