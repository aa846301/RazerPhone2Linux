#!/bin/sh
# One-shot rescue init: receive a complete /lib/modules tree over USB NCM,
# install it into the existing userdata rootfs, then continue normal boot.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mkdir -p /dev/pts /run /sys/kernel/config /sysroot
mount -t devpts devpts /dev/pts
mount -t tmpfs none /run
mount -t configfs none /sys/kernel/config
mdev -s

g=/sys/kernel/config/usb_gadget/module-rescue
mkdir -p "$g/configs/c.1" "$g/strings/0x409" \
	 "$g/configs/c.1/strings/0x409"
echo 0x0525 > "$g/idVendor"
echo 0xa4a7 > "$g/idProduct"
echo 0x0200 > "$g/bcdUSB"
echo 0x0100 > "$g/bcdDevice"
echo 0xef > "$g/bDeviceClass"
echo 0x02 > "$g/bDeviceSubClass"
echo 0x01 > "$g/bDeviceProtocol"
echo "aura-module-rescue" > "$g/strings/0x409/serialnumber"
echo "Razer" > "$g/strings/0x409/manufacturer"
echo "Razer Phone 2 module rescue" > "$g/strings/0x409/product"
echo "ACM + NCM module rescue" > "$g/configs/c.1/strings/0x409/configuration"
echo 250 > "$g/configs/c.1/MaxPower"

mkdir -p "$g/functions/acm.usb0" "$g/functions/ncm.usb0"
echo "02:de:ad:be:ef:02" > "$g/functions/ncm.usb0/host_addr"
echo "02:de:ad:be:ef:01" > "$g/functions/ncm.usb0/dev_addr"
ln -s "$g/functions/acm.usb0" "$g/configs/c.1/acm.usb0"
ln -s "$g/functions/ncm.usb0" "$g/configs/c.1/ncm.usb0"

udc=$(ls /sys/class/udc | head -n 1)
[ -n "$udc" ] || exec /bin/sh
echo "$udc" > "$g/UDC"
sleep 2
ifconfig usb0 192.168.137.133 netmask 255.255.255.0 up

# UFS is built in on the SDM845 7.1 configuration. Wait for userdata and use
# PARTLABEL first, then the known Razer partition as a fallback.
rootdev=""
waited=0
while [ "$waited" -lt 40 ]; do
	mdev -s
	for dev in /dev/sd[a-z][0-9]*; do
		[ -b "$dev" ] || continue
		if [ "$(blkid -s PARTLABEL -o value "$dev" 2>/dev/null)" = "userdata" ]; then
			rootdev="$dev"
			break 2
		fi
	done
	sleep 1
	waited=$((waited + 1))
done
[ -n "$rootdev" ] || rootdev=/dev/sda14
mount -t ext4 -o rw "$rootdev" /sysroot || exec /bin/sh

echo "module-rescue-ready" > /dev/kmsg
echo "Waiting for module archive on 192.168.137.133:9000" > /dev/ttyGS0

# The host sends an uncompressed tar with paths rooted at lib/modules/.
rm -rf /sysroot/lib/modules
mkdir -p /sysroot/lib/modules
if ! nc -l -p 9000 | tar -xpf - -C /sysroot; then
	echo "module archive receive failed" > /dev/ttyGS0
	exec /bin/sh </dev/ttyGS0 >/dev/ttyGS0 2>&1
fi

mount --bind /proc /sysroot/proc
mount --bind /sys /sysroot/sys
mount --bind /dev /sysroot/dev
mount --bind /dev/pts /sysroot/dev/pts
chroot /sysroot depmod -a 7.1.0-rc1-sdm845-printer
echo "module-rescue-installed" > /dev/kmsg

# Release the UDC so the rootfs service can create its normal ACM+NCM gadget.
echo "" > "$g/UDC"
rm -f "$g/configs/c.1/acm.usb0" "$g/configs/c.1/ncm.usb0"
rmdir "$g/functions/acm.usb0" "$g/functions/ncm.usb0" 2>/dev/null || true

umount /sysroot/dev/pts
umount /sysroot/dev
umount /sysroot/sys
umount /sysroot/proc
umount /dev/pts
umount /proc
umount /sys
exec switch_root /sysroot /usr/lib/systemd/systemd
