#!/bin/bash
# probe while partitions are mounted (persistent dir)
set -euo pipefail

REAL_HOME=$(getent passwd "${SUDO_USER:-$(whoami)}" | cut -d: -f6)
FWDIR="$REAL_HOME/razorphone2linux/fw-extract-tmp/out"

VENDOR_MNT="$FWDIR/vendor-mnt"
MODEM_MNT="$FWDIR/modem-mnt"

mountpoint -q "$VENDOR_MNT" || mount -o ro,loop "$FWDIR/vendor-raw.img" "$VENDOR_MNT"
mountpoint -q "$MODEM_MNT"  || mount -o ro,loop "$FWDIR/modem-raw.img"  "$MODEM_MNT" || \
    mount -o ro,loop,uid=0,gid=0 "$FWDIR/modem-raw.img" "$MODEM_MNT" || true

echo "=== modem partition: filesystem type ==="
file "$FWDIR/modem-raw.img"
echo "=== modem top-level (all files, 2 levels deep) ==="
find "$MODEM_MNT" -maxdepth 2 2>/dev/null | head -30 || echo "(empty or not mounted)"

echo ""
echo "=== vendor/firmware/ FULL listing ==="
ls "$VENDOR_MNT/firmware/" 2>/dev/null

echo ""
echo "=== find a630 in vendor (all subdirs) ==="
find "$VENDOR_MNT" -iname "*a630*" 2>/dev/null

echo ""
echo "=== find ath10k in vendor ==="
find "$VENDOR_MNT" -iname "*ath10k*" -o -type d -iname "*WCN*" 2>/dev/null

echo ""
echo "=== vendor/lib/firmware (if exists) ==="
ls "$VENDOR_MNT/lib/firmware/" 2>/dev/null | head -10 || echo "(no lib/firmware)"
