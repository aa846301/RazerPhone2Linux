#!/bin/sh
# Production boot initramfs init
# Uses busybox switch_root to avoid klibc run-init validation bug

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

USB_CONSOLE_ATTACHED=0
USB_GADGET_READY=0

ensure_ttygs0_node() {
    [ -e /dev/ttyGS0 ] && return 0
    [ -f /sys/class/tty/ttyGS0/dev ] || return 0
    local dev major minor
    dev=$(cat /sys/class/tty/ttyGS0/dev 2>/dev/null)
    major=${dev%:*}; minor=${dev#*:}
    [ -n "$major" ] && [ -n "$minor" ] && mknod /dev/ttyGS0 c "$major" "$minor"
}

attach_usb_console() {
    ensure_ttygs0_node
    if [ "$USB_CONSOLE_ATTACHED" -eq 0 ] && [ -c /dev/ttyGS0 ]; then
        exec >/dev/ttyGS0 2>&1
        USB_CONSOLE_ATTACHED=1
    fi
}

mount_fs() {
    mkdir -p "$2"
    mount -t "$3" "$1" "$2"
}

setup_usb_gadget() {
    [ "$USB_GADGET_READY" -eq 1 ] && return 0
    [ -d /sys/kernel/config/usb_gadget ] || return 0
    local udc_name
    udc_name=$(ls /sys/class/udc 2>/dev/null | head -n 1)
    [ -n "$udc_name" ] || return 0

    local g=/sys/kernel/config/usb_gadget/g1
    mkdir -p "$g/configs/c.1" "$g/strings/0x409" "$g/configs/c.1/strings/0x409"
    # Linux Foundation CDC ACM - Windows installs COM port driver for this
    echo 0x0525 > "$g/idVendor"; echo 0xa4a7 > "$g/idProduct"
    echo 0x0200 > "$g/bcdUSB";   echo 0x0100 > "$g/bcdDevice"
    echo 0x02 > "$g/bDeviceClass"; echo 0x02 > "$g/bDeviceSubClass"
    echo 0x01 > "$g/bDeviceProtocol"
    echo 'aura-linux' > "$g/strings/0x409/serialnumber"
    echo 'Razer' > "$g/strings/0x409/manufacturer"
    echo 'Razer Phone 2 Linux Console' > "$g/strings/0x409/product"
    echo 'ACM' > "$g/configs/c.1/strings/0x409/configuration"
    echo 120 > "$g/configs/c.1/MaxPower"

    local func_dir="$g/functions/acm.usb0"
    mkdir -p "$func_dir" 2>/dev/null || func_dir="$g/functions/serial.usb0"
    mkdir -p "$func_dir" 2>/dev/null || return 0
    [ -L "$g/configs/c.1/$(basename "$func_dir")" ] || \
        ln -s "$func_dir" "$g/configs/c.1/$(basename "$func_dir")"

    echo "$udc_name" > "$g/UDC" 2>/dev/null || return 0
    USB_GADGET_READY=1
    sleep 1
    ensure_ttygs0_node
}

cmdline_has() {
    grep -qw "$1" /proc/cmdline 2>/dev/null
}

populate_partlabels() {
    mkdir -p /dev/disk/by-partlabel

    # sysfs scan: works for UFS/SCSI
    for blk in /sys/class/block/*; do
        [ -f "$blk/partition" ] || continue
        local partname major minor node label_path
        partname=$(cat "$blk/partname" 2>/dev/null)
        [ -n "$partname" ] || continue
        major=$(grep '^MAJOR=' "$blk/uevent" 2>/dev/null | cut -d= -f2)
        minor=$(grep '^MINOR=' "$blk/uevent" 2>/dev/null | cut -d= -f2)
        node="/dev/$(basename "$blk")"
        label_path="/dev/disk/by-partlabel/$partname"
        if [ ! -e "$node" ] && [ -n "$major" ] && [ -n "$minor" ]; then
            mknod "$node" b "$major" "$minor" 2>/dev/null || true
        fi
        if [ ! -e "$label_path" ] && [ -e "$node" ]; then
            ln -sf "$node" "$label_path"
        fi
        [ "$partname" = "userdata" ] && echo "[boot] sysfs: userdata -> $node"
    done

    # blkid scan: picks up any UFS partitions not yet in sysfs partname
    if command -v blkid >/dev/null 2>&1; then
        local _dev _label
        _dev=""; _label=""
        blkid -s PARTLABEL -o export /dev/sd[a-z]* /dev/mmcblk* 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                DEVNAME=*) _dev="${line#DEVNAME=}" ;;
                PARTLABEL=*)
                    _label="${line#PARTLABEL=}"
                    local lp="/dev/disk/by-partlabel/$_label"
                    [ -e "$lp" ] || { ln -sf "$_dev" "$lp"; [ "$_label" = "userdata" ] && echo "[boot] blkid: userdata -> $_dev"; }
                    ;;
            esac
        done
    fi
}

partition_count() {
    local count=0
    for blk in /sys/class/block/*; do
        [ -f "$blk/partition" ] || continue
        count=$((count + 1))
    done
    echo "$count"
}

probe_root_candidate() {
    local candidate="$1" probe_dir=/run/root-probe
    echo "[boot] probing root candidate: $candidate" >&2
    if [ ! -b "$candidate" ]; then
        echo "[boot] candidate is not a block device: $candidate" >&2
        return 1
    fi
    mkdir -p "$probe_dir"
    umount "$probe_dir" 2>/dev/null || true
    # Try rw first (needed to replay ext4 journal), fall back to ro
    if ! mount -t ext4 -o rw "$candidate" "$probe_dir" 2>/dev/null; then
        echo "[boot] rw probe failed for $candidate, trying ro" >&2
        if ! mount -t ext4 -o ro "$candidate" "$probe_dir" 2>/dev/null; then
            echo "[boot] ext4 probe failed for $candidate" >&2
            return 1
        fi
    fi
    if [ -x "$probe_dir/usr/lib/systemd/systemd" ] || \
       [ -x "$probe_dir/sbin/init" ] || \
       [ -f "$probe_dir/etc/os-release" ]; then
        umount "$probe_dir" 2>/dev/null || true
        echo "[boot] root candidate accepted: $candidate" >&2
        echo "$candidate"
        return 0
    fi
    umount "$probe_dir" 2>/dev/null || true
    echo "[boot] ext4 ok but no Linux root found on $candidate" >&2
    return 1
}

find_root() {
    # 1. Parse root= from cmdline (supports PARTUUID=, /dev/..., by-partlabel/)
    local root_arg dev
    root_arg=$(
        tr ' ' '\n' < /proc/cmdline |
            grep '^root=' |
            sed 's/root=//' |
            grep -Ev '^(/dev/dm-|/dev/mapper/)' |
            tail -1
    )

    if [ -z "$root_arg" ]; then
        root_arg=/dev/disk/by-partlabel/userdata
        echo "[boot] ignoring Android bootloader root, using $root_arg" >&2
    fi

    case "$root_arg" in
        PARTUUID=*)
            local partuuid="${root_arg#PARTUUID=}"
            dev=$(blkid -t "PARTUUID=$partuuid" -o device 2>/dev/null | head -1)
            if [ -n "$dev" ]; then
                echo "[boot] PARTUUID $partuuid -> $dev" >&2
                probe_root_candidate "$dev" && return 0
            fi
            ;;
        /dev/disk/by-partlabel/*)
            local label="${root_arg#/dev/disk/by-partlabel/}"
            echo "[boot] cmdline wants partlabel: $label" >&2
            # Razer Phone 2 userdata is /dev/sda14 in the factory GPT.  Prefer
            # the direct block node in this tiny initramfs to avoid hangs in
            # readlink/blkid over the large Android partition table.
            if [ "$label" = "userdata" ]; then
                echo "[boot] using fixed Razer userdata node /dev/sda14" >&2
                probe_root_candidate /dev/sda14 && return 0
            fi
            # Try via by-partlabel symlink (populated by populate_partlabels above)
            if [ -e "/dev/disk/by-partlabel/$label" ]; then
                dev=$(readlink -f "/dev/disk/by-partlabel/$label" 2>/dev/null || echo "/dev/disk/by-partlabel/$label")
                echo "[boot] $label -> $dev" >&2
                probe_root_candidate "$dev" && return 0
            else
                echo "[boot] by-partlabel symlink not ready for $label" >&2
            fi
            # Try blkid search
            echo "[boot] trying blkid PARTLABEL=$label" >&2
            dev=$(blkid -t "PARTLABEL=$label" -o device 2>/dev/null | head -1)
            if [ -n "$dev" ]; then
                echo "[boot] blkid PARTLABEL=$label -> $dev" >&2
                probe_root_candidate "$dev" && return 0
            fi
            ;;
        /dev/*)
            echo "[boot] cmdline root: $root_arg" >&2
            probe_root_candidate "$root_arg" && return 0
            ;;
    esac

    # 2. Try userdata via by-partlabel (populated by populate_partlabels)
    if [ -e /dev/disk/by-partlabel/userdata ]; then
        dev=$(readlink -f /dev/disk/by-partlabel/userdata 2>/dev/null || echo /dev/disk/by-partlabel/userdata)
        probe_root_candidate "$dev" && return 0
    fi

    # 3. Hardcoded SDM845 Razer Phone 2 userdata partition candidates
    for c in /dev/sda14 /dev/sda17 /dev/sda18 /dev/sda19 /dev/sda20 /dev/sda16 /dev/sda6; do
        probe_root_candidate "$c" && return 0
    done

    # 4. Broad scan
    for c in /dev/sd[a-z][0-9]* /dev/mmcblk*p*; do
        probe_root_candidate "$c" && return 0
    done
    return 1
}

# --- Main ---
mount_fs none /proc proc
mount_fs none /sys sysfs
mount_fs none /dev devtmpfs
mkdir -p /dev/pts
mount_fs devpts /dev/pts devpts
mount_fs none /run tmpfs
mkdir -p /sys/kernel/config
mount -t configfs none /sys/kernel/config 2>/dev/null || true

# Trigger uevent processing so kernel creates block device nodes in devtmpfs
mdev -s 2>/dev/null || true

# Load UFS PHY driver (compiled as module in production kernel)
# Without this, ufshc-qcom cannot bind the QMP PHY -> UFS never probes -> no /dev/sda
if [ -f /lib/modules/phy-qcom-qmp-ufs.ko ]; then
    insmod /lib/modules/phy-qcom-qmp-ufs.ko 2>/dev/null && \
        echo '[boot] UFS PHY module loaded' || \
        echo '[boot] UFS PHY insmod failed (may already be built-in)'
else
    echo '[boot] UFS PHY module not found in initramfs (assuming built-in)'
fi

setup_usb_gadget
attach_usb_console

echo '[boot] Razer Phone 2 - Starting Linux...'
echo "[boot] kernel: $(uname -r)"

# Wait for UFS storage to enumerate (SDM845 UFS can take ~5-10s)
waited=0
while [ "$waited" -lt 40 ]; do
    setup_usb_gadget
    attach_usb_console
    mdev -s 2>/dev/null || true
    [ -e /dev/sda ] && echo "[boot] /dev/sda found at ${waited}s" && break
    [ -e /dev/mmcblk0 ] && echo "[boot] /dev/mmcblk0 found at ${waited}s" && break
    sleep 1
    waited=$((waited + 1))
    echo "[boot] waiting for storage... ${waited}s"
done

echo "[boot] Populating /dev/disk/by-partlabel..."
populate_partlabels

echo "[boot] Waiting for partitions/rootfs..."
waited=0
while [ "$waited" -lt 20 ]; do
    mdev -s 2>/dev/null || true
    populate_partlabels
    parts=$(partition_count)
    [ -e /dev/disk/by-partlabel/userdata ] && echo "[boot] userdata label ready at ${waited}s" && break
    [ "$parts" -gt 0 ] && echo "[boot] partition nodes ready: $parts at ${waited}s" && break
    sleep 1
    waited=$((waited + 1))
done

echo "[boot] Finding root filesystem..."
ROOT_DEV=$(find_root || true)

if [ -z "$ROOT_DEV" ]; then
    echo '[boot] ERROR: no root filesystem found!'
    echo '[boot] Entering emergency shell...'
    exec /bin/sh
fi

echo "[boot] Mounting $ROOT_DEV at /sysroot..."
mkdir -p /sysroot
if ! mount -t ext4 -o rw "$ROOT_DEV" /sysroot; then
    echo '[boot] rw mount failed, trying ro...'
    if ! mount -t ext4 -o ro "$ROOT_DEV" /sysroot; then
        echo '[boot] ERROR: mount failed!'
        exec /bin/sh
    fi
fi

# Make /run available in new root
mkdir -p /sysroot/run

if cmdline_has razer_fb_clear=0; then
    echo '[boot] Preserving framebuffer content (razer_fb_clear=0)...'
else
    echo '[boot] Clearing framebuffer (prevent garbled display)...'
    # Clear fb0 to black so the fbdev UI starts with a clean canvas.
    if [ -c /dev/fb0 ]; then
        dd if=/dev/zero of=/dev/fb0 bs=4096 count=4096 2>/dev/null || true
        echo '[boot] fb0 cleared'
    fi
fi

echo '[boot] Switching to real root...'

if cmdline_has razer_chroot_shell=1; then
    echo '[boot] Entering rootfs chroot shell (debug, no switch_root)...'
    mkdir -p /sysroot/dev /sysroot/proc /sysroot/sys /sysroot/run
    mount --bind /dev /sysroot/dev 2>/dev/null || true
    mount --bind /proc /sysroot/proc 2>/dev/null || true
    mount --bind /sys /sysroot/sys 2>/dev/null || true
    mount --bind /run /sysroot/run 2>/dev/null || true
    ensure_ttygs0_node
    if [ -c /dev/ttyGS0 ]; then
        exec /bin/busybox chroot /sysroot /bin/sh -i </dev/ttyGS0 >/dev/ttyGS0 2>&1
    fi
    exec /bin/busybox chroot /sysroot /bin/sh -i
fi

if cmdline_has razer_rootfs_debug_init=1; then
    cat > /run/init-codex-debug <<'DEBUG_INIT_EOF'
#!/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if [ -c /dev/ttyGS0 ]; then
    exec </dev/ttyGS0 >/dev/ttyGS0 2>&1
fi

echo '[rootfs-debug-init] started as PID 1'
echo "[rootfs-debug-init] kernel: $(uname -r)"
echo '[rootfs-debug-init] cmdline:'
cat /proc/cmdline 2>/dev/null || true
echo '[rootfs-debug-init] mounts:'
mount | head -20
echo '[rootfs-debug-init] /proc/filesystems cgroup lines:'
grep -i cgroup /proc/filesystems 2>/dev/null || true
echo '[rootfs-debug-init] cgroup mount probe:'
mkdir -p /sys/fs/cgroup 2>/dev/null || true
mount -t cgroup2 none /sys/fs/cgroup 2>&1 || true
mount | grep -i cgroup 2>/dev/null || true
echo '[rootfs-debug-init] essential pseudo-fs directories:'
ls -ld /dev /proc /sys /run /sys/fs/cgroup 2>/dev/null || true
echo '[rootfs-debug-init] rootfs:'
cat /etc/os-release 2>/dev/null || true
echo '[rootfs-debug-init] modules:'
ls -la "/lib/modules/$(uname -r)" 2>/dev/null || true
echo '[rootfs-debug-init] systemd binary:'
ls -la /usr/lib/systemd/systemd /sbin/init /bin/sh 2>/dev/null || true
echo '[rootfs-debug-init] systemd linked libraries:'
ldd /usr/lib/systemd/systemd 2>/dev/null || true
echo '[rootfs-debug-init] systemd offline test (max 12s, non-PID1):'
if command -v timeout >/dev/null 2>&1; then
    timeout 12s env SYSTEMD_LOG_LEVEL=debug /usr/lib/systemd/systemd --test --system 2>&1 | head -160 || true
else
    echo '[rootfs-debug-init] timeout command missing; skipping systemd --test to avoid hang'
fi
echo '[rootfs-debug-init] default target wants:'
ls -la /etc/systemd/system/default.target.wants 2>/dev/null || true
echo '[rootfs-debug-init] multi-user wants, first page:'
ls -la /etc/systemd/system/multi-user.target.wants 2>/dev/null | head -80 || true
echo '[rootfs-debug-init] last kernel messages:'
dmesg | tail -80 2>/dev/null || true

if grep -qw razer_exec_systemd=1 /proc/cmdline 2>/dev/null; then
    echo '[rootfs-debug-init] exec systemd requested'
    exec /usr/lib/systemd/systemd
fi

echo '[rootfs-debug-init] dropping to rootfs shell'
exec /bin/sh -i
DEBUG_INIT_EOF
    chmod 0755 /run/init-codex-debug
    mkdir -p /sysroot/dev /sysroot/proc /sysroot/sys /sysroot/run
    mount --move /dev /sysroot/dev 2>/dev/null || true
    mount --move /proc /sysroot/proc 2>/dev/null || true
    mount --move /sys /sysroot/sys 2>/dev/null || true
    mount --move /run /sysroot/run 2>/dev/null || true
    exec switch_root -c /dev/ttyGS0 /sysroot /run/init-codex-debug
fi

# Use explicit path - bypasses klibc run-init symlink resolution bug
if cmdline_has razer_root_shell=1; then
    mkdir -p /sysroot/dev /sysroot/proc /sysroot/sys /sysroot/run
    mount --move /dev /sysroot/dev 2>/dev/null || true
    mount --move /proc /sysroot/proc 2>/dev/null || true
    mount --move /sys /sysroot/sys 2>/dev/null || true
    mount --move /run /sysroot/run 2>/dev/null || true
    exec switch_root -c /dev/ttyGS0 /sysroot /bin/sh -i
else
    mkdir -p /sysroot/dev /sysroot/proc /sysroot/sys /sysroot/run
    mount --move /dev /sysroot/dev 2>/dev/null || true
    mount --move /proc /sysroot/proc 2>/dev/null || true
    mount --move /sys /sysroot/sys 2>/dev/null || true
    mount --move /run /sysroot/run 2>/dev/null || true
    exec switch_root -c /dev/ttyGS0 /sysroot /usr/lib/systemd/systemd
fi

echo '[boot] ERROR: switch_root failed!'
exec /bin/sh
