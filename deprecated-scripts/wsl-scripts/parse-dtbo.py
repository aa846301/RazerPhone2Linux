#!/usr/bin/env python3
import struct, os, subprocess, sys

TMPDIR = os.path.expanduser("~/razorphone2linux/fw-extract-tmp")
outdir = TMPDIR + "/dtbo-out"
os.makedirs(outdir, exist_ok=True)

with open(TMPDIR + "/dtbo.img", "rb") as f:
    data = f.read()

(magic, total_size, header_size, dt_entry_size, dt_entry_count, dt_entries_offset,
 page_size, version) = struct.unpack_from(">IIIIIIII", data, 0)

print(f"magic=0x{magic:08x} total={total_size} hdr_size={header_size}")
print(f"entry_size={dt_entry_size} count={dt_entry_count} entries_offset={dt_entries_offset}")

for i in range(dt_entry_count):
    off = dt_entries_offset + i * dt_entry_size
    dt_size, dt_offset = struct.unpack_from(">II", data, off)
    dtb_data = data[dt_offset:dt_offset + dt_size]
    fname = f"{outdir}/dtbo-entry-{i:02d}.dtb"
    with open(fname, "wb") as out:
        out.write(dtb_data)
    print(f"  [{i}] offset=0x{dt_offset:x} size={dt_size} -> {os.path.basename(fname)}")

print("\nDecompiling DTBs...")
for i in range(dt_entry_count):
    dtb = f"{outdir}/dtbo-entry-{i:02d}.dtb"
    dts = f"{outdir}/dtbo-entry-{i:02d}.dts"
    r = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", "-o", dts, dtb],
                       capture_output=True)
    if r.returncode == 0:
        print(f"  OK: dtbo-entry-{i:02d}.dts")
    else:
        print(f"  FAIL: {r.stderr.decode()[:80]}")

print("\n=== Panel search ===")
import glob
keywords = ["jdi", "nt36", "sharp", "novatek", "dsi-panel", "panel-name",
            "nt36830", "nt36672", "fhd", "qhd", "1440", "2560", "144hz",
            "synaptics", "panel@"]
for dts_file in sorted(glob.glob(f"{outdir}/*.dts")):
    with open(dts_file) as f:
        for lineno, line in enumerate(f, 1):
            ll = line.lower()
            for kw in keywords:
                if kw in ll:
                    print(f"  {os.path.basename(dts_file)}:{lineno}: {line.rstrip()}")
                    break
