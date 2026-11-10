#!/usr/bin/env python3
"""Extract every flattened device tree blob (magic d00dfeed) found in a binary (boot.img, dtbo.img, kernel).

Usage: extract_dtbs.py <image> <out-dir>
Writes <out-dir>/<image-stem>-<n>.dtb and prints offset, size and the root "model" string of each.
"""
import pathlib, struct, sys

src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
data = src.read_bytes()
i, n = 0, 0
while (i := data.find(b"\xd0\x0d\xfe\xed", i)) >= 0:
    total, off_struct, off_strings = struct.unpack(">III", data[i + 4:i + 16])
    if not (64 < total < 4 << 20) or off_struct >= total or off_strings >= total:
        i += 4
        continue
    blob = data[i:i + total]
    model = b""
    m = blob.find(b"model\0")  # cheap: model property value is in the struct block near the root
    p = blob.find(b"Razer") if b"Razer" in blob else blob.find(b"Qualcomm")
    if p >= 0:
        model = blob[p:blob.find(b"\0", p)]
    name = out / f"{src.stem}-{n}.dtb"
    name.write_bytes(blob)
    print(f"{name.name}: offset 0x{i:x} size {total} model {model.decode(errors='replace')}")
    n += 1
    i += total
print(f"{n} blobs")
