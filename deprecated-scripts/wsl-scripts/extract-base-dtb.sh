#!/bin/bash
# 從 boot.img 的 kernel 段搜尋附加的 DTB (FDT magic)
# 直接用 Windows 路徑，不需要先解壓
ZIP="/mnt/c/repo/razorphone2linux/aura-p-release-3201-user-full.zip"
OUTDIR="$HOME/razorphone2linux/android-fdt"
WIN_OUT="/mnt/c/repo/razorphone2linux/android-fdt"

mkdir -p "$OUTDIR" "$WIN_OUT"

# 先解壓 boot.img 到 /tmp
mkdir -p /tmp/rom-extract
unzip -o "$ZIP" 'aura-p-release-3201-user-full/aura-p-release-3201/boot.img' -d /tmp/rom-extract/ 2>&1 | tail -2

python3 << 'PYEOF'
import struct, os

BOOT = "/tmp/rom-extract/aura-p-release-3201-user-full/aura-p-release-3201/boot.img"
OUTDIR = os.path.expanduser("~/razorphone2linux/android-fdt")
WIN_OUT = "/mnt/c/repo/razorphone2linux/android-fdt"

with open(BOOT, 'rb') as f:
    data = f.read()

kernel_size  = struct.unpack_from('<I', data, 8)[0]
page_size    = struct.unpack_from('<I', data, 36)[0]

kernel_start = page_size
kernel_end   = kernel_start + kernel_size

print(f"Kernel section: [{kernel_start:#x} - {kernel_end:#x}] ({kernel_size//1024}KB)")

# FDT magic in big-endian
FDT_MAGIC = b'\xd0\x0d\xfe\xed'

# Search in kernel section for DTB
found = []
pos = kernel_start
while pos < kernel_end - 4:
    idx = data.find(FDT_MAGIC, pos, kernel_end)
    if idx == -1:
        break
    total_size = struct.unpack_from('>I', data, idx + 4)[0]
    # Sanity: DTB should be 50KB - 5MB
    if 50*1024 < total_size < 5*1024*1024:
        found.append((idx, total_size))
        print(f"  FDT candidate: offset={idx:#x} ({idx}), size={total_size} ({total_size//1024}KB)")
    pos = idx + 4

if not found:
    print("No valid FDT found in kernel section.")
    print("Trying full image scan...")
    pos = 0
    while pos < len(data) - 4:
        idx = data.find(FDT_MAGIC, pos)
        if idx == -1:
            break
        total_size = struct.unpack_from('>I', data, idx + 4)[0]
        if 50*1024 < total_size < 5*1024*1024:
            found.append((idx, total_size))
            print(f"  FDT candidate: offset={idx:#x}, size={total_size//1024}KB")
        pos = idx + 4

for i, (off, size) in enumerate(found):
    out = os.path.join(OUTDIR, f"android-base-{i:02d}.dtb")
    win = os.path.join(WIN_OUT, f"android-base-{i:02d}.dtb")
    chunk = data[off:off+size]
    with open(out, 'wb') as f:
        f.write(chunk)
    with open(win, 'wb') as f:
        f.write(chunk)
    print(f"Saved: {out}")
PYEOF
