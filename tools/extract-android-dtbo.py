#!/usr/bin/env python3
"""Extract DTBs from an Android DTBO table image."""

import argparse
import pathlib
import struct


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    data = args.image.read_bytes()
    if len(data) < 32:
        raise SystemExit("DTBO image is too small")

    header = struct.unpack_from(">8I", data, 0)
    magic, total_size, header_size, entry_size, count, entries_offset, _, _ = header
    if magic != 0xD7B7AB1E:
        raise SystemExit(f"unsupported DTBO magic: 0x{magic:08x}")
    if total_size > len(data) or header_size < 32 or entry_size < 8:
        raise SystemExit("invalid DTBO table header")

    args.output.mkdir(parents=True, exist_ok=True)
    for index in range(count):
        offset = entries_offset + index * entry_size
        dt_size, dt_offset = struct.unpack_from(">2I", data, offset)
        end = dt_offset + dt_size
        if end > len(data):
            raise SystemExit(f"entry {index} exceeds image size")
        target = args.output / f"dtbo-entry-{index:02d}.dtb"
        target.write_bytes(data[dt_offset:end])
        print(target)


if __name__ == "__main__":
    main()
