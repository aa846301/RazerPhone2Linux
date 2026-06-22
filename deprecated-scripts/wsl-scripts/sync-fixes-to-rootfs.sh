#!/bin/bash
# sync-fixes-to-rootfs.sh
# Patch key changed files into rootfs-sparse.img without full rootfs rebuild.
# Run in WSL after applying fixes via SSH to persist them for next flash.
#
# Usage:
#   bash wsl-scripts/sync-fixes-to-rootfs.sh            # sync from local wsl-scripts/
#   bash wsl-scripts/sync-fixes-to-rootfs.sh --from-device  # pull live files from device first
#
# What gets synced:
#   - wsl-scripts/usb-gadget-setup-ncm.sh -> /usr/local/bin/usb-gadget-setup.sh
#   - wsl-scripts/post-internet-setup.sh   -> /root/post-internet-setup.sh
#   - etc/modules-load.d/ath10k.conf       -> /etc/modules-load.d/ath10k.conf
#   - Any file listed in PATCH_MANIFEST    -> target path in rootfs

set -euo pipefail

WIN_REPO="/mnt/c/repo/razorphone2linux"
SPARSE_IMG="$WIN_REPO/output/rootfs-sparse.img"
RAW_IMG="/tmp/rootfs-patch.img"
MNT="/tmp/rootfs-patch-mnt"
LOG_PREFIX="[sync-rootfs]"

FROM_DEVICE=0
DEVICE_IP="192.168.137.133"
DEVICE_USER="klipper"
SSH_KEY="/home/$(logname 2>/dev/null || echo dinochang)/.ssh/razer-phone"

for arg in "$@"; do
    case "$arg" in
        --from-device) FROM_DEVICE=1 ;;
        --ip=*) DEVICE_IP="${arg#--ip=}" ;;
    esac
done

log() { echo "$LOG_PREFIX $*"; }
die() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

[ -f "$SPARSE_IMG" ] || die "rootfs-sparse.img not found at $SPARSE_IMG"
command -v simg2img >/dev/null 2>&1 || die "simg2img not found (apt install android-sdk-libsparse-utils)"
command -v img2simg >/dev/null 2>&1 || die "img2simg not found"

# ── Optional: pull live changes from device via SSH ─────────────────────────
if [ "$FROM_DEVICE" -eq 1 ]; then
    log "Pulling live files from device $DEVICE_IP..."
    mkdir -p "$WIN_REPO/wsl-scripts/from-device"

    pull_file() {
        local src="$1" dest_dir="$2"
        mkdir -p "$WIN_REPO/wsl-scripts/from-device$dest_dir"
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
            "${DEVICE_USER}@${DEVICE_IP}" \
            "echo klipper | sudo -S cat '$src' 2>/dev/null" \
            > "$WIN_REPO/wsl-scripts/from-device${src}" 2>/dev/null \
            && log "  pulled: $src" \
            || log "  SKIP (not found): $src"
    }

    pull_file "/usr/local/bin/usb-gadget-setup.sh"   ""
    pull_file "/root/post-internet-setup.sh"          ""
    pull_file "/etc/modules-load.d/ath10k.conf"       ""
    pull_file "/etc/NetworkManager/system-connections/CimforceTw-Guest.nmconnection" ""
fi

# ── Decompress sparse → raw ─────────────────────────────────────────────────
log "Converting sparse to raw ($(du -h "$SPARSE_IMG" | cut -f1))..."
rm -f "$RAW_IMG"
simg2img "$SPARSE_IMG" "$RAW_IMG"
log "Raw image: $(du -h "$RAW_IMG" | cut -f1)"

# ── Mount ──────────────────────────────────────────────────────────────────
mkdir -p "$MNT"
if mountpoint -q "$MNT"; then
    umount "$MNT" 2>/dev/null || true
fi
mount -o loop "$RAW_IMG" "$MNT"
log "Mounted at $MNT"

cleanup() {
    umount "$MNT" 2>/dev/null || true
    rm -f "$RAW_IMG"
}
trap cleanup EXIT

# ── Patch manifest ──────────────────────────────────────────────────────────
# Format: SRC_IN_REPO  DEST_IN_ROOTFS  MODE
PATCHES=(
    "wsl-scripts/usb-gadget-setup-ncm.sh          /usr/local/bin/usb-gadget-setup.sh  755"
    "wsl-scripts/post-internet-setup.sh            /root/post-internet-setup.sh        755"
)

apply_patch() {
    local src="$WIN_REPO/$1"
    local dest="$MNT/$2"
    local mode="$3"

    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        chmod "$mode" "$dest"
        log "  patched: $2"
    else
        log "  SKIP (src not found): $1"
    fi
}

log "Applying patches..."
for patch in "${PATCHES[@]}"; do
    read -r src dest mode <<< "$patch"
    apply_patch "$src" "$dest" "$mode"
done

# ── ath10k autoload ─────────────────────────────────────────────────────────
log "  ensuring ath10k autoload config..."
mkdir -p "$MNT/etc/modules-load.d"
if [ ! -f "$MNT/etc/modules-load.d/ath10k.conf" ]; then
    printf 'ath10k_core\nath10k_snoc\n' > "$MNT/etc/modules-load.d/ath10k.conf"
    log "  created: /etc/modules-load.d/ath10k.conf"
else
    log "  exists:  /etc/modules-load.d/ath10k.conf"
fi

# ── fbcon persistence: ensure boot param is set ─────────────────────────────
# Note: fbcon=map:99 is in boot cmdline (boot.img), not rootfs - nothing to do here.
log "  fbcon=map:99 is in boot.img cmdline, no rootfs change needed."

# ── From-device overrides ───────────────────────────────────────────────────
if [ "$FROM_DEVICE" -eq 1 ]; then
    FROM_DIR="$WIN_REPO/wsl-scripts/from-device"
    for f in "$FROM_DIR"/**/* "$FROM_DIR"/*; do
        [ -f "$f" ] || continue
        rel="${f#$FROM_DIR}"
        dest="$MNT$rel"
        mkdir -p "$(dirname "$dest")"
        cp "$f" "$dest"
        log "  from-device: $rel"
    done 2>/dev/null || true
fi

# ── Sync & unmount ─────────────────────────────────────────────────────────
sync
umount "$MNT"
trap - EXIT

# ── Re-sparse ──────────────────────────────────────────────────────────────
log "Converting raw back to sparse..."
SPARSE_BACKUP="${SPARSE_IMG%.img}-$(date +%Y%m%d-%H%M%S).img.bak"
cp "$SPARSE_IMG" "$SPARSE_BACKUP"
img2simg "$RAW_IMG" "$SPARSE_IMG"
rm -f "$RAW_IMG"

log ""
log "Done. Patched rootfs-sparse.img:"
log "  $(ls -lh "$SPARSE_IMG")"
log "  Backup saved: $SPARSE_BACKUP"
log ""
log "Flash with:"
log "  fastboot flash userdata output\\rootfs-sparse.img"
