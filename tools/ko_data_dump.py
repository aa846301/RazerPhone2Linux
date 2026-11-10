#!/usr/bin/env python3
"""Dump initialised data of named symbols from an (unstripped, relocatable) aarch64 kernel module as u32 words.
usage: ko_data_dump.py <module.ko> <symbol> [symbol...]   (needs aarch64-linux-gnu-readelf/objdump in PATH)"""
import re
import struct
import subprocess
import sys

ko, syms = sys.argv[1], sys.argv[2:]
out = subprocess.run(["aarch64-linux-gnu-readelf", "-sW", ko], capture_output=True, text=True).stdout
secs = subprocess.run(["aarch64-linux-gnu-readelf", "-SW", ko], capture_output=True, text=True).stdout
sec = {}
for m in re.finditer(r"\[\s*(\d+)\]\s+(\S+)\s+\S+\s+[0-9a-f]+\s+([0-9a-f]+)\s+([0-9a-f]+)", secs):
    sec[int(m.group(1))] = (m.group(2), int(m.group(3), 16), int(m.group(4), 16))
data = open(ko, "rb").read()
for line in out.splitlines():
    p = line.split()
    if len(p) >= 8 and p[-1] in syms:
        value, size, ndx = int(p[1], 16), int(p[2]), p[6]
        if not ndx.isdigit():
            print(p[-1], "undefined/abs"); continue
        name, off, _ = sec[int(ndx)]
        blob = data[off + value: off + value + size]
        words = struct.unpack("<%dI" % (len(blob) // 4), blob[: len(blob) // 4 * 4])
        print(f"{p[-1]} ({name}+{value:#x}, {size} bytes):")
        for i in range(0, len(words), 8):
            print("  " + " ".join(f"{w:08x}" for w in words[i:i + 8]))
