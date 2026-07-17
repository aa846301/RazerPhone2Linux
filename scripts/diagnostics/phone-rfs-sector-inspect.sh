#!/usr/bin/env bash
set -euo pipefail

echo "=== RFS partition summary ==="
for part in modemst1 modemst2 fsg fsc nvdef_a nvdef_b; do
    dev="/dev/disk/by-partlabel/$part"
    echo "=== $part ==="
    readlink -f "$dev" || true
    blockdev --getsize64 "$dev" 2>/dev/null || true
    sha256sum "$dev" 2>/dev/null || true
done

echo "=== RFS sectors requested before MSS fatal ==="
for item in "modemst1 1" "modemst2 1" "modemst2 2"; do
    set -- $item
    part="$1"
    sector="$2"
    dev="/dev/disk/by-partlabel/$part"
    echo "=== $part sector $sector sha256 ==="
    dd if="$dev" bs=512 skip="$sector" count=1 status=none | sha256sum
    echo "=== $part sector $sector first 128 bytes ==="
    dd if="$dev" bs=512 skip="$sector" count=1 status=none | xxd -g1 -l 128
done
