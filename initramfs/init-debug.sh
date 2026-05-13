#!/bin/sh

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

USB_CONSOLE_ATTACHED=0
USB_GADGET_READY=0

ensure_ttygs0_node() {
    local dev major minor

    [ -e /dev/ttyGS0 ] && return 0
    [ -f /sys/class/tty/ttyGS0/dev ] || return 0

    dev=$(cat /sys/class/tty/ttyGS0/dev 2>/dev/null)
    major=${dev%:*}
    minor=${dev#*:}

    [ -n "$major" ] && [ -n "$minor" ] && mknod /dev/ttyGS0 c "$major" "$minor"
}

attach_usb_console() {
    ensure_ttygs0_node

    if [ "$USB_CONSOLE_ATTACHED" -eq 0 ] && [ -c /dev/ttyGS0 ]; then
        echo '--- ttyGS0 detected, redirecting initramfs logs ---' > /dev/ttyGS0
        exec >/dev/ttyGS0 2>&1
        USB_CONSOLE_ATTACHED=1
    fi
}

drop_debug_shell() {
    attach_usb_console
    echo 'Entering debug shell...'
    exec /bin/sh
}

cmdline_has() {
    grep -qw "$1" /proc/cmdline
}

mount_fs() {
    mkdir -p "$2"
    mount -t "$3" "$1" "$2"
}

setup_usb_gadget() {
    local gadget_dir config_dir strings_dir config_strings_dir func_dir udc_name

    [ "$USB_GADGET_READY" -eq 1 ] && return 0
    [ -d /sys/class/udc ] || return 0
    [ -d /sys/kernel/config ] || return 0

    [ -d /sys/kernel/config/usb_gadget ] || return 0

    udc_name=$(ls /sys/class/udc 2>/dev/null | head -n 1)
    [ -n "$udc_name" ] || return 0

    gadget_dir=/sys/kernel/config/usb_gadget/g1
    config_dir=$gadget_dir/configs/c.1
    strings_dir=$gadget_dir/strings/0x409
    config_strings_dir=$config_dir/strings/0x409

    mkdir -p "$strings_dir" "$config_strings_dir" "$config_dir"
    echo 0x18d1 > "$gadget_dir/idVendor"
    echo 0x4ee7 > "$gadget_dir/idProduct"
    echo 0x0200 > "$gadget_dir/bcdUSB"
    echo 0x0100 > "$gadget_dir/bcdDevice"
    echo 0x02 > "$gadget_dir/bDeviceClass"
    echo 0x02 > "$gadget_dir/bDeviceSubClass"
    echo 0x01 > "$gadget_dir/bDeviceProtocol"
    echo '0123456789ABCDEF' > "$strings_dir/serialnumber"
    echo 'Razer' > "$strings_dir/manufacturer"
    echo 'Razer Phone 2 Debug' > "$strings_dir/product"
    echo 'Debug ACM' > "$config_strings_dir/configuration"
    echo 120 > "$config_dir/MaxPower"

    func_dir=$gadget_dir/functions/acm.usb0
    mkdir -p "$func_dir" 2>/dev/null || func_dir=''
    if [ -z "$func_dir" ] || [ ! -d "$func_dir" ]; then
        func_dir=$gadget_dir/functions/serial.usb0
        mkdir -p "$func_dir" 2>/dev/null || return 0
    fi

    [ -L "$config_dir/$(basename "$func_dir")" ] || ln -s "$func_dir" "$config_dir/$(basename "$func_dir")"

    echo "$udc_name" > "$gadget_dir/UDC" 2>/dev/null || return 0
    USB_GADGET_READY=1
    sleep 2
    ensure_ttygs0_node
}

print_header() {
    echo
    echo '=== Razer Phone 2 debug initramfs ==='
    echo "kernel: $(uname -a)"
    echo '--- cmdline ---'
    cat /proc/cmdline
}

print_block_state() {
    echo '--- /proc/partitions ---'
    cat /proc/partitions
    echo '--- partlabel scan ---'
}

populate_partlabels() {
    mkdir -p /dev/disk/by-partlabel

    # First pass: sysfs partname (works for eMMC/MMC, not UFS/SCSI)
    for blk in /sys/class/block/*; do
        [ -f "$blk/partition" ] || continue
        [ -f "$blk/partname" ] || continue
        [ -f "$blk/uevent" ] || continue

        partname=$(cat "$blk/partname" 2>/dev/null)
        [ -n "$partname" ] || continue

        major=$(grep '^MAJOR=' "$blk/uevent" | cut -d= -f2)
        minor=$(grep '^MINOR=' "$blk/uevent" | cut -d= -f2)
        node="/dev/$(basename "$blk")"
        label_path="/dev/disk/by-partlabel/$partname"

        if [ ! -e "$node" ] && [ -n "$major" ] && [ -n "$minor" ]; then
            mknod "$node" b "$major" "$minor"
        fi
        if [ ! -e "$label_path" ] && [ -e "$node" ]; then
            ln -s "$node" "$label_path"
        fi
        echo "  [sysfs] $partname -> $node"
    done

    # Second pass: blkid for UFS/SCSI devices that lack sysfs partname
    if command -v blkid >/dev/null 2>&1; then
        blkid -s PARTLABEL -o export /dev/sd?* 2>/dev/null | while read -r line; do
            case "$line" in
                DEVNAME=*)
                    _dev=${line#DEVNAME=}
                    ;;
                PARTLABEL=*)
                    _label=${line#PARTLABEL=}
                    label_path="/dev/disk/by-partlabel/$_label"
                    if [ ! -e "$label_path" ] && [ -n "$_dev" ]; then
                        ln -sf "$_dev" "$label_path"
                        echo "  [blkid] $_label -> $_dev"
                    fi
                    ;;
            esac
        done
    fi

    # Always ensure /dev/disk/by-partlabel/userdata exists for sda14
    # (SDM845 Razer Phone 2 hardcoded mapping)
    if [ ! -e /dev/disk/by-partlabel/userdata ] && [ -b /dev/sda14 ]; then
        ln -sf /dev/sda14 /dev/disk/by-partlabel/userdata
        echo "  [hardcoded] userdata -> /dev/sda14"
    fi
}

print_drm_state() {
    echo '--- drm state ---'
    if [ -d /sys/class/drm ]; then
        for node in /sys/class/drm/*; do
            [ -e "$node" ] || continue
            echo "[$(basename "$node")]"
            [ -f "$node/status" ] && echo "  status=$(cat "$node/status")"
            [ -f "$node/modes" ] && echo "  modes=$(cat "$node/modes" | tr '\n' ' ')"
        done
    else
        echo '  /sys/class/drm not present'
    fi
}

print_usb_state() {
    echo '--- usb state ---'
    if [ -d /sys/class/udc ]; then
        ls /sys/class/udc 2>/dev/null || true
    else
        echo '  no /sys/class/udc'
    fi

    if [ -d /sys/kernel/config/usb_gadget ]; then
        echo '  configfs gadget available'
    fi

    if [ -d /sys/class/tty ]; then
        ls /sys/class/tty/ttyGS* 2>/dev/null || echo '  no ttyGS* yet'
    fi

    if [ -f /sys/kernel/config/usb_gadget/g1/UDC ]; then
        echo "  gadget udc=$(cat /sys/kernel/config/usb_gadget/g1/UDC 2>/dev/null)"
    fi
}

probe_root_candidate() {
    local candidate probe_dir mount_err

    candidate="$1"
    probe_dir=/run/root-probe

    [ -b "$candidate" ] || return 1

    mkdir -p "$probe_dir"
    umount "$probe_dir" 2>/dev/null || true

    # Mount rw so kernel can replay journal (ro fails with EUCLEAN if needs_recovery set)
    mount_err=$(mount -t ext4 -o rw "$candidate" "$probe_dir" 2>&1)
    if [ $? -ne 0 ]; then
        echo "  probe $candidate: mount failed: $mount_err" >&2
        return 1
    fi

    # Ubuntu Noble uses merged-usr: /sbin -> usr/sbin, /sbin/init -> /usr/lib/systemd/systemd
    # Check multiple possible init paths
    if [ -x "$probe_dir/sbin/init" ] || \
       [ -x "$probe_dir/usr/sbin/init" ] || \
       [ -x "$probe_dir/usr/lib/systemd/systemd" ] || \
       [ -f "$probe_dir/etc/os-release" ]; then
        umount "$probe_dir" 2>/dev/null || true
        echo "$candidate"
        return 0
    fi

    echo "  probe $candidate: ext4 ok but no init found (not a Linux rootfs)" >&2
    umount "$probe_dir" 2>/dev/null || true
    return 1
}

find_root() {
    local candidate

    for candidate in \
        /dev/disk/by-partlabel/userdata \
        /dev/sda14 \
        /dev/sda17 /dev/sda18 /dev/sda19 /dev/sda20 /dev/sda16; do
        probe_root_candidate "$candidate" && return 0
    done

    for candidate in /dev/sd[a-z][0-9]* /dev/mmcblk*p*; do
        probe_root_candidate "$candidate" && return 0
    done

    return 1
}

diag_loop() {
    while true; do
        setup_usb_gadget
        attach_usb_console
        echo '--- diagnostic loop tick ---'
        print_block_state
        populate_partlabels
        print_drm_state
        print_usb_state
        sleep 10
    done
}

stay_in_initramfs() {
    echo 'Staying in initramfs for debug. Current root candidate state follows.'
    echo 'Use diag_loop for repeated output, or inspect manually in the shell.'
    drop_debug_shell
}

print_rootfs_hint() {
    echo 'No mountable ext4 rootfs with /sbin/init was found.'
    echo 'Most likely cause: userdata does not contain the Linux rootfs image.'
    echo 'Expected host-side flash sequence:'
    echo '  fastboot flash boot_a output/boot-observable.img'
    echo '  fastboot flash userdata output/rootfs-sparse.img'
    echo '  fastboot --disable-verity --disable-verification flash vbmeta output/vbmeta_disabled.img'
}

mount_fs none /proc proc
mount_fs none /sys sysfs
mount_fs none /dev devtmpfs
mount_fs devpts /dev/pts devpts
mkdir -p /sys/kernel/config
mount -t configfs none /sys/kernel/config 2>/dev/null || true

print_header
echo 'Waiting for storage...'
setup_usb_gadget
attach_usb_console

waited=0
while [ "$waited" -lt 15 ]; do
    setup_usb_gadget
    attach_usb_console
    if [ -e /dev/sda ] || [ -e /dev/mmcblk0 ]; then
        break
    fi
    sleep 1
    waited=$((waited + 1))
    echo "  waiting... ${waited}s"
done

print_block_state
populate_partlabels
print_drm_state
print_usb_state

ROOT_DEV=$(find_root || true)

if cmdline_has 'debug_stay_initramfs=1'; then
    echo 'debug_stay_initramfs=1 detected'
    echo "Root candidate: ${ROOT_DEV:-<none>}"
    [ -n "$ROOT_DEV" ] || print_rootfs_hint
    stay_in_initramfs
fi

if [ -z "$ROOT_DEV" ]; then
    echo 'ERROR: root device not found'
    print_rootfs_hint
    echo 'Entering debug shell. Run diag_loop for repeated on-screen output.'
    drop_debug_shell
fi

echo "Mounting root: $ROOT_DEV"
mkdir -p /sysroot
if ! mount -t ext4 "$ROOT_DEV" /sysroot; then
    echo 'RW mount failed, retrying read-only'
    if ! mount -t ext4 -o ro "$ROOT_DEV" /sysroot; then
        echo 'ERROR: root mount failed'
        drop_debug_shell
    fi
fi

if [ ! -x /sysroot/sbin/init ] && \
   [ ! -x /sysroot/usr/lib/systemd/systemd ]; then
    echo 'ERROR: /sysroot/sbin/init missing or not executable'
    drop_debug_shell
fi

echo 'Switching to real root...'
umount /dev/pts || true
umount /proc || true
umount /sys || true
exec switch_root /sysroot /sbin/init
