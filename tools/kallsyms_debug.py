#!/usr/bin/env python3
"""Debug helper for kallsyms_extract.py: print layout guesses around the token table / markers."""
import struct
import sys

img = open(sys.argv[1], "rb").read()
ttab = int(sys.argv[2], 0)
m_end = ttab & ~7
print("u64 before token table:")
for p in range(m_end - 8 * 6, m_end, 8):
    print(f"  {p:#x}: {struct.unpack_from('<Q', img, p)[0]:#x}")
# walk back as u64 while decreasing
p = m_end - 8
while struct.unpack_from("<Q", img, p)[0] == 0:
    p -= 8
last = struct.unpack_from("<Q", img, p)[0]
cnt = 0
prev = None
while True:
    v = struct.unpack_from("<Q", img, p)[0]
    if prev is not None and v >= prev:
        break
    prev = v
    cnt += 1
    if v == 0:
        break
    p -= 8
print(f"markers: start {p:#x} count {cnt} last {last:#x} first {struct.unpack_from('<Q', img, p)[0]:#x}")
print("u64 before markers:")
for q in range(p - 8 * 4, p + 16, 8):
    print(f"  {q:#x}: {struct.unpack_from('<Q', img, q)[0]:#x}")
approx = p - last
print(f"approx names start <= {approx:#x}")
for q in range((approx & ~7) - 8192, (approx & ~7) + 16, 8):
    v = struct.unpack_from("<Q", img, q)[0]
    if (cnt - 1) * 256 < v <= cnt * 256:
        print(f"  candidate num_syms {v} at {q:#x}; bytes after: {img[q+8:q+24].hex()}")
