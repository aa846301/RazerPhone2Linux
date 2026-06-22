#!/bin/bash
set -euo pipefail
TMPDIR="$HOME/razorphone2linux/fw-extract-tmp"
ROM="/mnt/c/repo/razorphone2linux/aura-p-release-3201-user-full.zip"
PREFIX="aura-p-release-3201-user-full/aura-p-release-3201"

mkdir -p "$TMPDIR/dtbo-out"

# Extract dtbo.img
if [ ! -f "$TMPDIR/dtbo.img" ]; then
    echo "Extracting dtbo.img..."
    unzip -p "$ROM" "$PREFIX/dtbo.img" > "$TMPDIR/dtbo.img"
fi
echo "dtbo.img: $(ls -lh $TMPDIR/dtbo.img | awk '{print $5}')"
file "$TMPDIR/dtbo.img"
echo ""
echo "Magic bytes:"
xxd "$TMPDIR/dtbo.img" | head -3

# Parse DTBO table and extract individual DTBs
# Android DTBO format: magic 0xedfe0dd0 per-entry, or MKDTBOIMG table
python3 - <<'PYEOF'
import struct, os, sys

TMPDIR = os.environ['HOME'] + "/razorphone2linux/fw-extract-tmp"
outdir = TMPDIR + "/dtbo-out"
os.makedirs(outdir, exist_ok=True)

with open(TMPDIR + "/dtbo.img", "rb") as f:
    data = f.read()

# Check for DTBO image table magic: d7b7ab1e (big-endian)
DTBO_MAGIC = 0xd7b7ab1e
magic = struct.unpack(">I", data[:4])[0]
print(f"Magic: 0x{magic:08x}")

if magic == DTBO_MAGIC:
    # DTBO image header
    # struct dt_table_header { magic, total_size, header_size, dt_entry_size, dt_entry_count, dt_entries_offset, ... }
    (magic, total_size, header_size, dt_entry_size, dt_entry_count, dt_entries_offset,
     page_size, version) = struct.unpack(">IIIIIIII", data[:32])
    print(f"DTBO table: {dt_entry_count} entries, entry_size={dt_entry_size}")

    for i in range(dt_entry_count):
        offset = dt_entries_offset + i * dt_entry_size
        (dt_size, dt_offset, id_, rev, flags) = struct.unpack(">IIIII", data[offset:offset+20])
        dtb_data = data[dt_offset:dt_offset+dt_size]
        fname = f"{outdir}/dtbo-entry-{i:02d}.dtb"
        with open(fname, "wb") as out:
            out.write(dtb_data)
        print(f"  Entry {i}: offset=0x{dt_offset:x} size={dt_size} -> {os.path.basename(fname)}")
else:
    # Maybe a raw DTB
    print("Not DTBO format, trying as raw DTB")
    with open(outdir + "/dtbo-raw.dtb", "wb") as out:
        out.write(data)
PYEOF

echo ""
echo "Extracted DTBs:"
ls -lh "$TMPDIR/dtbo-out/"

# Decompile all DTBs to DTS
echo ""
echo "Decompiling DTBs..."
for dtb in "$TMPDIR/dtbo-out/"*.dtb; do
    dts="${dtb%.dtb}.dts"
    dtc -I dtb -O dts -o "$dts" "$dtb" 2>/dev/null && echo "  OK: $(basename $dts)"
done

# Search for panel info
echo ""
echo "=== Panel name search ==="
grep -h -i "panel-name\|jdi\|nt36\|sharp\|novatek\|synaptics\|compatible.*panel\|dsi-panel" \
    "$TMPDIR/dtbo-out/"*.dts 2>/dev/null | sort -u | head -30
