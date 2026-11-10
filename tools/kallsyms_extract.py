#!/usr/bin/env python3
"""Recover the kallsyms symbol table from a raw arm64 Linux 4.9-era Image (CONFIG_KALLSYMS_BASE_RELATIVE,
64-bit markers). Tolerates zero padding between the tables. Writes "address type name" lines.
usage: kallsyms_extract.py <Image> <out.txt>"""
import struct
import sys

img = open(sys.argv[1], "rb").read()
n = len(img)


def back_nonzero(p):
    """Largest q < p with img[q] != 0."""
    q = p - 1
    while img[q] == 0:
        q -= 1
    return q


# 1. token_index: 256 strictly increasing u16 starting at 0; token table right before it (after padding)
tidx = None
for off in range(0, n - 512, 4):
    if img[off:off + 2] != b"\0\0":
        continue
    v = struct.unpack_from("<256H", img, off)
    if v[1] == 0 or not all(0 < v[i + 1] - v[i] <= 80 for i in range(255)):
        continue
    e = back_nonzero(off)                    # last char of the last token
    last_start = img.rindex(b"\0", 0, e) + 1
    T = last_start - v[255]
    if T > 0 and all(img[T + v[i] - 1] == 0 for i in range(1, 256)) and \
            sum(32 <= img[T + v[i]] < 127 for i in range(256)) >= 200:
        tidx, ttab, tok_index = off, T, v
        break
assert tidx, "token index not found"
tokens = []
for i in range(256):
    s = ttab + tok_index[i]
    tokens.append(img[s:img.index(b"\0", s)].decode("latin1"))

# 2. markers: u64 array before the token table, strictly increasing, first element 0
p = (back_nonzero(ttab) & ~7)              # last (non-zero) marker
vals = []
prev = None
while p > 0:
    val = struct.unpack_from("<Q", img, p)[0]
    if prev is not None and val >= prev:
        break
    vals.append(val)
    prev = val
    if val == 0:
        break
    p -= 8
assert vals and vals[-1] == 0, "markers not found"
markers_start, markers = p, vals[::-1]

# 3. names: find N such that walking entries from N hits every marker offset exactly
names = None
hi = (back_nonzero(markers_start) + 1 - markers[-1]) & ~7
for N in range(hi, hi - (1 << 18), -8):
    q, ok = N, True
    for mi in range(1, len(markers)):
        for _ in range(256):
            q += img[q] + 1
        if q - N != markers[mi]:
            ok = False
            break
    if ok and img[N] != 0:
        names = N
        break
assert names, f"names not found (markers {len(markers)}, last {markers[-1]:#x})"
num_syms = (len(markers) - 1) * 256
q = names + markers[-1]
while img[q] != 0 and q < markers_start:
    q += img[q] + 1
    num_syms += 1

# 4. num_syms (u64), relative base (u64), offsets (u32[]) precede the names, each possibly padded
p = (back_nonzero(names) & ~7)
assert struct.unpack_from("<Q", img, p)[0] == num_syms, \
    f"num_syms mismatch: walked {num_syms}, stored {struct.unpack_from('<Q', img, p)[0]}"
# On a relocatable kernel kallsyms_relative_base is filled in by a RELA relocation and is 0 in the file, so the
# last non-zero word before num_syms is the last offset (the highest symbol, never 0). Use the nominal arm64
# 4.9 link address for display; only differences matter for disassembly.
rel_base = 0xffffff8008080000
end = ((back_nonzero(p) + 4) & ~3)
start = end - 4 * num_syms
offsets = struct.unpack_from("<%dI" % num_syms, img, start)
best = (sum(1 for i in range(1, num_syms) if offsets[i] >= offsets[i - 1]), offsets, start)

with open(sys.argv[2], "w") as out:
    q = names
    for i in range(num_syms):
        ln = img[q]
        s = "".join(tokens[b] for b in img[q + 1:q + 1 + ln])
        q += ln + 1
        out.write(f"{rel_base + offsets[i]:016x} {s[0]} {s[1:]}\n")
print(f"{num_syms} symbols, relative base {rel_base:#x}, offsets @ {best[2]:#x} (monotonic {best[0]}/{num_syms}), "
      f"names @ {names:#x}, token table @ {ttab:#x}")
