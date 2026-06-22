#!/bin/bash
# ==========================================================================
# extract-android-fdt.sh
# 從 Android 工廠 ROM 的 boot.img / dtbo.img 提取 DTB，反編譯為 DTS
# ==========================================================================
set -euo pipefail

ZIP="/mnt/c/repo/razorphone2linux/aura-p-release-3201-user-full.zip"
ROMDIR="/tmp/rom-extract/aura-p-release-3201-user-full/aura-p-release-3201"
OUTDIR="$HOME/razorphone2linux/android-fdt"
WIN_OUT="/mnt/c/repo/razorphone2linux/android-fdt"

mkdir -p "$OUTDIR"
mkdir -p "$WIN_OUT"

# ---- 等 apt lock 釋放 ----
echo "=== 等待 apt lock ==="
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "  apt locked, waiting 3s..."; sleep 3
done

# ---- 工具安裝 ----
echo "=== 安裝工具 ==="
apt-get install -y device-tree-compiler python3 2>&1 | grep -E '^(Inst|Setting up|E:|already)' || true

# ---- 解壓 boot.img / dtbo.img ----
echo ""
echo "=== 解壓 boot.img 和 dtbo.img ==="
mkdir -p /tmp/rom-extract
unzip -o "$ZIP" \
    'aura-p-release-3201-user-full/aura-p-release-3201/boot.img' \
    'aura-p-release-3201-user-full/aura-p-release-3201/dtbo.img' \
    -d /tmp/rom-extract/ 2>&1 | grep -v "^Archive:"
ls -lh "$ROMDIR/"

# ---- boot.img → 提取 FDT ----
echo ""
echo "=== 解析 boot.img (Android v1 格式) ==="
BOOT="$ROMDIR/boot.img"

# 讀 boot image header (v1): pagesize at offset 36
PAGE_SIZE=$(python3 -c "
import struct, sys
with open('$BOOT','rb') as f:
    data = f.read(2048)
# magic(8) + kernel_size(4) + kernel_addr(4) + ramdisk_size(4) + ramdisk_addr(4)
# + second_size(4) + second_addr(4) + tags_addr(4) + page_size(4)
magic = data[0:8]
kernel_size  = struct.unpack_from('<I', data, 8)[0]
ramdisk_size = struct.unpack_from('<I', data, 16)[0]
second_size  = struct.unpack_from('<I', data, 24)[0]
page_size    = struct.unpack_from('<I', data, 36)[0]
os_version   = struct.unpack_from('<I', data, 40)[0]
# v1 also has recovery_dtbo_size at offset 1632
recovery_dtbo_size = struct.unpack_from('<I', data, 1632)[0]
recovery_dtbo_off  = struct.unpack_from('<Q', data, 1636)[0]
print(f'magic={magic}')
print(f'page_size={page_size}')
print(f'kernel_size={kernel_size}')
print(f'ramdisk_size={ramdisk_size}')
print(f'second_size={second_size}')
print(f'recovery_dtbo_size={recovery_dtbo_size}')
print(f'recovery_dtbo_offset={recovery_dtbo_off}')
def roundup(n, p): return ((n + p - 1) // p) * p
header_pages = 1
kernel_pages  = roundup(kernel_size, page_size) // page_size
ramdisk_pages = roundup(ramdisk_size, page_size) // page_size
second_pages  = roundup(second_size, page_size) // page_size
dtbo_pages    = roundup(recovery_dtbo_size, page_size) // page_size
dtb_offset    = (header_pages + kernel_pages + ramdisk_pages + second_pages + dtbo_pages) * page_size
print(f'dtb_offset={dtb_offset}')
") 2>&1

echo "$PAGE_SIZE"

# 從計算的 dtb_offset 用 Python 提取 DTB
python3 << 'PYEOF'
import struct, os, sys

BOOT = "/tmp/rom-extract/aura-p-release-3201-user-full/aura-p-release-3201/boot.img"
OUTDIR = os.path.expanduser("~/razorphone2linux/android-fdt")

with open(BOOT, 'rb') as f:
    data = f.read()

kernel_size  = struct.unpack_from('<I', data, 8)[0]
ramdisk_size = struct.unpack_from('<I', data, 16)[0]
second_size  = struct.unpack_from('<I', data, 24)[0]
page_size    = struct.unpack_from('<I', data, 36)[0]
recovery_dtbo_size = struct.unpack_from('<I', data, 1632)[0]

def roundup(n, p):
    return ((n + p - 1) // p) * p if n > 0 else 0

header_off  = page_size
kernel_off  = header_off + roundup(kernel_size, page_size)
ramdisk_off = kernel_off + roundup(ramdisk_size, page_size)
second_off  = ramdisk_off + roundup(second_size, page_size)
dtbo_off    = second_off + roundup(recovery_dtbo_size, page_size)
# v1 DTB is appended after recovery_dtbo
# Check if there's a DTB size field at offset 1644
dtb_size = struct.unpack_from('<I', data, 1644)[0] if len(data) > 1648 else 0

print(f"page_size={page_size}")
print(f"kernel={kernel_size} bytes at offset {header_off}")
print(f"ramdisk={ramdisk_size} bytes")
print(f"second={second_size} bytes")
print(f"recovery_dtbo={recovery_dtbo_size} bytes")
print(f"dtb_size={dtb_size} bytes (from header field)")
print(f"calculated dtb offset={dtbo_off}")

# Try to find DTB by magic: FDT magic = 0xd00dfeed (BE) = bytes d0 0d fe ed
FDT_MAGIC_BE = b'\xd0\x0d\xfe\xed'

# Search from dtbo_off onwards
search_start = dtbo_off
found_offsets = []
pos = search_start
while pos < len(data) - 4:
    idx = data.find(FDT_MAGIC_BE, pos)
    if idx == -1:
        break
    found_offsets.append(idx)
    pos = idx + 1
    if len(found_offsets) > 10:
        break

print(f"Found FDT magic at offsets: {found_offsets}")

if found_offsets:
    # Use the first (primary) DTB
    fdt_off = found_offsets[0]
    # DTB total size is at offset +4 in the FDT header (big-endian)
    fdt_total = struct.unpack_from('>I', data, fdt_off + 4)[0]
    print(f"Primary DTB: offset={fdt_off}, size={fdt_total} bytes")

    out_path = os.path.join(OUTDIR, "razer-phone2-boot.dtb")
    with open(out_path, 'wb') as f:
        f.write(data[fdt_off:fdt_off+fdt_total])
    print(f"Saved: {out_path}")
else:
    print("No FDT magic found in boot.img after dtbo section!")
PYEOF

# ---- dtbo.img → 提取所有 DTB ----
echo ""
echo "=== 解析 dtbo.img ==="
python3 << 'PYEOF2'
import struct, os

DTBO = "/tmp/rom-extract/aura-p-release-3201-user-full/aura-p-release-3201/dtbo.img"
OUTDIR = os.path.expanduser("~/razorphone2linux/android-fdt")

with open(DTBO, 'rb') as f:
    data = f.read()

# DT Table header format (Android DTBO)
# magic(4) + total_size(4) + header_size(4) + dt_entry_size(4) + dt_entry_count(4) + dt_entry_start(4) + ...
MAGIC = 0xd7b7ab1e
magic = struct.unpack_from('>I', data, 0)[0]
if magic != MAGIC:
    print(f"ERROR: Not a DTBO image (magic={hex(magic)}, expected {hex(MAGIC)})")
    # Try FDT magic directly (some devices use raw DTB concatenation)
    FDT_MAGIC = b'\xd0\x0d\xfe\xed'
    pos = 0
    idx = 0
    while pos < len(data):
        off = data.find(FDT_MAGIC, pos)
        if off == -1:
            break
        size = struct.unpack_from('>I', data, off+4)[0]
        out = os.path.join(OUTDIR, f"dtbo-raw-{idx:02d}.dtb")
        with open(out, 'wb') as f:
            f.write(data[off:off+size])
        print(f"  Saved raw DTB #{idx}: offset={off}, size={size} -> {out}")
        pos = off + size
        idx += 1
else:
    total_size   = struct.unpack_from('>I', data, 4)[0]
    header_size  = struct.unpack_from('>I', data, 8)[0]
    entry_size   = struct.unpack_from('>I', data, 12)[0]
    entry_count  = struct.unpack_from('>I', data, 16)[0]
    entry_start  = struct.unpack_from('>I', data, 20)[0]
    print(f"DTBO: magic OK, {entry_count} entries, entry_size={entry_size}")

    for i in range(entry_count):
        off = entry_start + i * entry_size
        dt_size   = struct.unpack_from('>I', data, off)[0]
        dt_offset = struct.unpack_from('>I', data, off+4)[0]
        # Extract
        dtb_data = data[dt_offset:dt_offset+dt_size]
        out = os.path.join(OUTDIR, f"dtbo-entry-{i:02d}.dtb")
        with open(out, 'wb') as f:
            f.write(dtb_data)
        # Check FDT magic for description
        if dtb_data[:4] == b'\xd0\x0d\xfe\xed':
            print(f"  Entry {i:02d}: offset={dt_offset}, size={dt_size} -> {out} [FDT OK]")
        else:
            print(f"  Entry {i:02d}: offset={dt_offset}, size={dt_size} -> {out} [magic={dtb_data[:4].hex()}]")
PYEOF2

# ---- 反編譯所有 DTB → DTS ----
echo ""
echo "=== 反編譯 DTB → DTS ==="
for dtb in "$OUTDIR"/*.dtb; do
    dts="${dtb%.dtb}.dts"
    echo "  dtc: $(basename $dtb) -> $(basename $dts)"
    dtc -I dtb -O dts -o "$dts" "$dtb" 2>/dev/null || echo "    WARNING: dtc failed for $dtb"
done

# ---- 同步到 Windows ----
echo ""
echo "=== 同步到 Windows ==="
cp -fv "$OUTDIR"/*.dtb "$OUTDIR"/*.dts "$WIN_OUT/" 2>/dev/null || true

echo ""
echo "=== 完成 ==="
ls -lh "$WIN_OUT"/
