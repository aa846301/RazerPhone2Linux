#!/usr/bin/env python3
"""Extract the kernel from an Android boot.img (header v0-v2) and gunzip it if needed (appended DTBs are dropped).
usage: bootimg_kernel.py <boot.img> <out Image>"""
import struct
import sys
import zlib

src, dst = sys.argv[1:3]
d = open(src, "rb").read()
assert d[:8] == b"ANDROID!", "not an Android boot image"
ksize, kaddr, rsize, raddr, ssize, saddr, tags, page = struct.unpack("<8I", d[8:40])
k = d[page:page + ksize]
print(f"kernel {ksize} bytes, ramdisk {rsize}, page {page}, cmdline: {d[64:64+512].split(b'\\0')[0].decode(errors='replace')[:200]}")
if k[:2] == b"\x1f\x8b":
    o = zlib.decompressobj(31)
    img = o.decompress(k)
    print(f"gunzip -> {len(img)} bytes, trailing (dtb etc.) {len(o.unused_data)} bytes")
    k = img
open(dst, "wb").write(k)
print("magic", k[56:60])
