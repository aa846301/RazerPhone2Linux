#!/bin/bash
set -euo pipefail

WORKDIR=~/razorphone2linux
OUTPUT=$WORKDIR/output
KDIR=$WORKDIR/kernel/linux
KVER=$(ls $OUTPUT/modules_install/lib/modules/ | head -1)

echo '=== Creating boot.img ==='

# Step 0: Rebuild Image.gz-dtb with current DTB
echo '[0/3] Rebuilding Image.gz-dtb with latest DTB...'
DTB_SRC=$OUTPUT/sdm845-razer-aura.dtb
if [ ! -f "$DTB_SRC" ]; then
    echo "ERROR: $DTB_SRC not found. Compile DTB first."
    exit 1
fi
# Find Image.gz (kernel without DTB)
if [ ! -f "$OUTPUT/Image.gz" ]; then
    echo "ERROR: $OUTPUT/Image.gz not found."
    exit 1
fi
cat "$OUTPUT/Image.gz" "$DTB_SRC" > "$OUTPUT/Image.gz-dtb"
echo "  Image.gz-dtb rebuilt: $(du -h $OUTPUT/Image.gz-dtb | cut -f1)  (DTB: $(du -h $DTB_SRC | cut -f1))"

# Step 1: Create busybox initramfs with auto-boot to Ubuntu
echo '[1/3] Creating initramfs...'
INITRD_DIR=$(mktemp -d)
mkdir -p $INITRD_DIR/{bin,sbin,dev,proc,sys,run,sysroot,lib,mnt}
mkdir -p $INITRD_DIR/dev/pts

# Install busybox
BUSYBOX=$WORKDIR/busybox-aarch64
if [ ! -f "$BUSYBOX" ]; then
    echo "ERROR: $BUSYBOX not found."
    exit 1
fi
cp "$BUSYBOX" $INITRD_DIR/bin/busybox
chmod +x $INITRD_DIR/bin/busybox
# Create symlinks directly - no chroot needed (cross-arch x86_64 host cannot exec arm64)
for app in sh ash cat echo ls grep sed cut head tail sort uniq wc tr \
           find env test printf \
           mount umount mkdir rmdir rm cp mv ln chmod chown \
           dmesg sleep df free ps kill killall \
           mdev mknod mkfifo tty stty \
           ip ifconfig route hostname uname date id \
           findfs blkid; do
    ln -sf /bin/busybox $INITRD_DIR/bin/$app
done
for app in switch_root pivot_root mdev init; do
    ln -sf /bin/busybox $INITRD_DIR/sbin/$app
done

# Write init script
cat > $INITRD_DIR/init << 'INIT_EOF'
#!/bin/sh
# Razer Phone 2 initramfs - auto-boots to Ubuntu on userdata

mount -t proc     none /proc
mount -t sysfs    none /sys
mount -t devtmpfs none /dev 2>/dev/null
mdev -s 2>/dev/null
mkdir -p /dev/pts
mount -t devpts none /dev/pts 2>/dev/null

echo ""
echo "=== Razer Phone 2 initramfs ==="

# Wait for ttyGS0 (USB gadget serial)
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -e /dev/ttyGS0 ] && echo "=== ttyGS0 ready ===" && break
    sleep 0.3
done

# Wait for any block device to appear (UFS may be sde, sdf, not necessarily sda)
echo "=== Waiting for block devices... ==="
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    ls /sys/class/block/ 2>/dev/null | grep -q 'sd[a-z][0-9]' && echo "=== Block partitions ready ===" && break
    mdev -s 2>/dev/null
    sleep 0.5
done

echo "=== All partitions in /proc/partitions ==="
cat /proc/partitions

# Find userdata partition via sysfs GPT PARTNAME (works without udev/findfs)
# Kernel exports PARTNAME from GPT entry in /sys/class/block/<dev>/uevent
echo "=== Searching sysfs for PARTNAME=userdata ==="
ROOT_DEV=""
for uevent in /sys/class/block/*/uevent; do
    if grep -q 'PARTNAME=userdata' "$uevent" 2>/dev/null; then
        DEVNAME=$(grep '^DEVNAME=' "$uevent" | cut -d= -f2)
        ROOT_DEV="/dev/$DEVNAME"
        echo "=== Found: $ROOT_DEV ==="
        break
    fi
done

if [ -z "$ROOT_DEV" ] || [ ! -b "$ROOT_DEV" ]; then
    echo "=== FATAL: userdata partition not found via sysfs ==="
    echo "=== All PARTNAME entries in sysfs: ==="
    grep -r '^PARTNAME=' /sys/class/block/*/uevent 2>/dev/null
    echo "=== DEBUG SHELL (type 'exit' to halt) ==="
    exec /bin/sh
fi

echo "=== Mounting $ROOT_DEV (ext4)... ==="
# Show what's on the device before trying
echo "=== blkid $ROOT_DEV ==="
blkid "$ROOT_DEV" 2>&1 || true

if ! mount -t ext4 -o rw "$ROOT_DEV" /sysroot; then
    echo "=== Mount rw failed, checking dmesg for ext4 errors... ==="
    dmesg | grep -i "ext4\|EXT4\|sda14\|sde\|journal\|clean\|error\|corrupt" | tail -20
    echo "=== Trying ro... ==="
    if ! mount -t ext4 -o ro "$ROOT_DEV" /sysroot; then
        echo "=== ro also failed, trying without -t (auto-detect)... ==="
        mount -o rw "$ROOT_DEV" /sysroot 2>&1 || true
        if ! mountpoint -q /sysroot; then
            echo "=== All mount attempts failed. Full dmesg below: ==="
            dmesg | grep -i "ext4\|EXT4\|block\|scsi\|ufs\|sda\|mount\|error" | tail -30
            echo "=== Block device info: ==="
            blkid 2>&1 || true
            echo "=== (Is rootfs-sparse.img flashed to userdata?) ==="
            echo "=== DEBUG SHELL - type 'mount /dev/sda14 /sysroot' to retry ==="
            exec /bin/sh
        fi
    fi
fi

# Verify Ubuntu rootfs
if [ ! -f /sysroot/usr/lib/systemd/systemd ] && [ ! -f /sysroot/lib/systemd/systemd ]; then
    echo "=== WARNING: systemd not found in rootfs ==="
    ls /sysroot/
    echo "=== DEBUG SHELL ==="
    exec /bin/sh
fi

echo "=== Root mounted. Starting Ubuntu (systemd)... ==="
mount --move /proc /sysroot/proc 2>/dev/null || mount -t proc     none /sysroot/proc
mount --move /sys  /sysroot/sys  2>/dev/null || mount -t sysfs    none /sysroot/sys
mount --move /dev  /sysroot/dev  2>/dev/null || mount -t devtmpfs none /sysroot/dev

INIT_BIN=/lib/systemd/systemd
[ -f /sysroot/usr/lib/systemd/systemd ] && INIT_BIN=/usr/lib/systemd/systemd

exec switch_root /sysroot $INIT_BIN

echo "=== FATAL: switch_root failed! ==="
exec /bin/sh
INIT_EOF
chmod +x $INITRD_DIR/init

(cd $INITRD_DIR && find . | cpio -o -H newc 2>/dev/null | gzip) > $OUTPUT/initramfs.cpio.gz
rm -rf $INITRD_DIR
echo "  initramfs: $(du -h $OUTPUT/initramfs.cpio.gz | cut -f1)"

# Step 2: Create boot.img
echo '[2/3] Creating boot.img...'
# console=ttyGS0,115200 MUST be last so init gets stdin/stdout on USB serial
# earlycon + ttyMSM0 kept for UART debug (if hardware UART adapter available)
CMDLINE="earlycon=msm_geni_serial,0xA84000 console=ttyMSM0,115200n8 console=ttyGS0,115200 clk_ignore_unused pd_ignore_unused fw_devlink=permissive root=/dev/disk/by-partlabel/userdata rootfstype=ext4 rootwait rw loglevel=7 pcie_aspm=off"

python3 $WORKDIR/mkbootimg-tool/mkbootimg.py \
    --kernel $OUTPUT/Image.gz-dtb \
    --ramdisk $OUTPUT/initramfs.cpio.gz \
    --base 0x00000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --pagesize 4096 \
    --header_version 1 \
    --cmdline "$CMDLINE" \
    --os_version 14.0.0 \
    --os_patch_level 2024-01 \
    -o $OUTPUT/boot.img

echo "  boot.img: $(du -h $OUTPUT/boot.img | cut -f1)"

# Step 3: Create vbmeta (disabled)
echo '[3/3] Creating vbmeta_disabled.img...'
python3 << 'PYEOF'
import struct, os
data = bytearray(4096)
data[0:4] = b'AVB0'
struct.pack_into('>I', data, 4, 1)
struct.pack_into('>I', data, 8, 1)
struct.pack_into('>I', data, 120, 3)
outdir = os.path.expanduser('~/razorphone2linux/output')
with open(os.path.join(outdir, 'vbmeta_disabled.img'), 'wb') as f:
    f.write(bytes(data))
PYEOF
echo '  vbmeta_disabled.img created'

echo ''
echo '=== boot.img complete ==='
ls -lh $OUTPUT/boot.img $OUTPUT/vbmeta_disabled.img $OUTPUT/initramfs.cpio.gz $OUTPUT/Image.gz-dtb

# Copy to Windows output directory (for flash script)
WIN_OUTPUT=/mnt/c/repo/razorphone2linux/output
if [ -d "$WIN_OUTPUT" ]; then
    cp -f $OUTPUT/boot.img $WIN_OUTPUT/boot-observable.img
    echo "  Copied to Windows: $WIN_OUTPUT/boot-observable.img"
fi
