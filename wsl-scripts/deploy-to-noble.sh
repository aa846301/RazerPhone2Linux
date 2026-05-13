#!/bin/bash
# deploy-to-noble.sh
# Deploys updated files to rootfs-noble.img
set -e
IMG=/home/dinochang/razorphone2linux/rootfs/rootfs-noble.img
MNT=/tmp/noble-deploy-mnt
REPO=/mnt/c/repo/razorphone2linux

mkdir -p "$MNT"
mount "$IMG" "$MNT"
echo "Mounted $IMG at $MNT"

# 1. Updated USB gadget script (ACM + NCM)
cp "$REPO/wsl-scripts/usb-gadget-setup-ncm.sh" "$MNT/usr/local/bin/usb-gadget-setup.sh"
chmod 755 "$MNT/usr/local/bin/usb-gadget-setup.sh"
echo "gadget script: $(head -2 $MNT/usr/local/bin/usb-gadget-setup.sh | tail -1)"

# 2. Post-internet setup script
cp "$REPO/wsl-scripts/post-internet-setup.sh" "$MNT/root/post-internet-setup.sh"
chmod +x "$MNT/root/post-internet-setup.sh"
echo "setup script: $(wc -l < $MNT/root/post-internet-setup.sh) lines"

# 3. systemd-networkd config for usb0 (DHCP over CDC-NCM)
mkdir -p "$MNT/etc/systemd/network"
cat > "$MNT/etc/systemd/network/20-usb0.network" << 'NETEOF'
[Match]
Name=usb0

[Network]
DHCP=yes
LinkLocalAddressing=ipv6
NETEOF
echo "usb0 network config written"

# 4. Enable systemd-networkd
WANTS="$MNT/etc/systemd/system/multi-user.target.wants"
mkdir -p "$WANTS"
ln -sf /lib/systemd/system/systemd-networkd.service \
    "$WANTS/systemd-networkd.service" 2>/dev/null || true
echo "systemd-networkd enabled"

# 5. Verify NCM is present
COUNT=$(grep -c ncm "$MNT/usr/local/bin/usb-gadget-setup.sh" || true)
echo "NCM occurrences in gadget script: $COUNT"

umount "$MNT"
echo "DONE - noble.img updated"
