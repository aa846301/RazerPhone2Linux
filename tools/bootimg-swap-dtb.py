#!/usr/bin/env python3
"""Replace the DTB appended to the kernel of an Android boot image (v0/v1).

The Razer Phone 2 ABL loads Image.gz with an appended DTB. This keeps the
kernel, ramdisk, header fields and cmdline byte-identical, swaps only the DTB,
recomputes the mkbootimg id, and re-pads every section to the page size.

Usage: bootimg-swap-dtb.py IN.img NEW.dtb OUT.img
       bootimg-swap-dtb.py --extract IN.img OUTDIR   (writes Image.gz, dtb, ramdisk)
"""
import hashlib
import os
import struct
import sys

DTB_MAGIC = b"\xd0\x0d\xfe\xed"


def pad(n, ps):
    return (n + ps - 1) // ps * ps


def parse(data):
    if data[:8] != b"ANDROID!":
        raise SystemExit("not an Android boot image")
    (ks, ka, rs, ra, ss, sa, ta, ps, hv) = struct.unpack_from("<9I", data, 8)
    if hv not in (0, 1):
        raise SystemExit(f"unsupported header_version {hv}")
    off = ps
    kernel = data[off:off + ks]
    off += pad(ks, ps)
    ramdisk = data[off:off + rs]
    off += pad(rs, ps)
    second = data[off:off + ss]
    off += pad(ss, ps)
    rdtbo = b""
    if hv == 1:
        rdtbo_size = struct.unpack_from("<I", data, 1632)[0]
        rdtbo = data[off:off + rdtbo_size]
    return dict(ps=ps, hv=hv, kernel=kernel, ramdisk=ramdisk, second=second, rdtbo=rdtbo)


def split_kernel(kernel):
    i = kernel.find(DTB_MAGIC)
    if i <= 0:
        raise SystemExit("no appended DTB found in kernel section")
    total = struct.unpack(">I", kernel[i + 4:i + 8])[0]
    if i + total != len(kernel):
        raise SystemExit(f"appended DTB size mismatch: {i}+{total} != {len(kernel)}")
    return kernel[:i], kernel[i:]


def build(orig, img, new_kernel):
    ps, hv = img["ps"], img["hv"]
    hdr = bytearray(orig[:ps])
    struct.pack_into("<I", hdr, 8, len(new_kernel))
    # Same id as this project's tools/mkbootimg.py: sha1 over kernel and
    # ramdisk only (no second/recovery_dtbo, which this project never uses).
    sha = hashlib.sha1()
    for blob in (new_kernel, img["ramdisk"]):
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))
    # id field: 32 bytes after magic(8)+10*u32(40)+name(16)+cmdline(512) = 576
    hdr[576:608] = sha.digest().ljust(32, b"\0")
    out = bytearray(hdr)
    for blob in (new_kernel, img["ramdisk"], img["second"], img["rdtbo"]):
        out += blob + b"\0" * (pad(len(blob), ps) - len(blob))
    return bytes(out)


def main(argv):
    if len(argv) == 4 and argv[1] == "--extract":
        img = parse(open(argv[2], "rb").read())
        kgz, dtb = split_kernel(img["kernel"])
        os.makedirs(argv[3], exist_ok=True)
        for name, blob in (("Image.gz", kgz), ("dtb", dtb), ("ramdisk", img["ramdisk"])):
            open(os.path.join(argv[3], name), "wb").write(blob)
        return 0
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    orig = open(argv[1], "rb").read()
    img = parse(orig)
    kgz, _ = split_kernel(img["kernel"])
    new_dtb = open(argv[2], "rb").read()
    if new_dtb[:4] != DTB_MAGIC:
        raise SystemExit("new DTB has no FDT magic")
    out = build(orig, img, kgz + new_dtb)
    check = parse(out)
    assert check["ramdisk"] == img["ramdisk"] and split_kernel(check["kernel"])[1] == new_dtb
    open(argv[3], "wb").write(out)
    print(f"wrote {argv[3]} ({len(out)} bytes), sha256 {hashlib.sha256(out).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
