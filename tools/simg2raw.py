#!/usr/bin/env python3
"""Android sparse image -> raw image (like simg2img), no dependencies. Passes raw images through unchanged.
usage: simg2raw.py <in.img> <out.raw>"""
import shutil
import struct
import sys

src, dst = sys.argv[1:3]
with open(src, "rb") as f:
    hdr = f.read(28)
    magic, major, minor, fhs, chs, blksz, total_blks, total_chunks, _ = struct.unpack("<IHHHHIIII", hdr)
    if magic != 0xED26FF3A:
        f.close()
        shutil.copyfile(src, dst)
        print("not sparse, copied")
        sys.exit(0)
    f.seek(fhs)
    with open(dst, "wb") as o:
        for _ in range(total_chunks):
            ctype, _, csize, ctotal = struct.unpack("<HHII", f.read(chs))
            f.seek(chs - 12, 1) if chs > 12 else None
            n = csize * blksz
            if ctype == 0xCAC1:  # raw
                remaining = n
                while remaining:
                    buf = f.read(min(remaining, 1 << 20))
                    o.write(buf)
                    remaining -= len(buf)
            elif ctype == 0xCAC2:  # fill
                pat = f.read(4)
                o.write(pat * (n // 4))
            elif ctype == 0xCAC3:  # don't care
                o.seek(n, 1)
            elif ctype == 0xCAC4:  # crc
                f.read(4)
            else:
                sys.exit(f"bad chunk type {ctype:#x}")
        o.truncate(total_blks * blksz)
print(f"sparse -> raw: {total_blks * blksz} bytes")
