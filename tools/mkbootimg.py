#!/usr/bin/env python3
"""Minimal Android boot image packer for this project's boot.img layout."""

import argparse
import hashlib
import os
import struct
import sys


BOOT_MAGIC = b"ANDROID!"
BOOT_NAME_SIZE = 16
BOOT_ARGS_SIZE = 512
BOOT_EXTRA_ARGS_SIZE = 1024
BOOT_ID_SIZE = 32


def parse_int(value):
    return int(value, 0)


def parse_os_version(value):
    parts = value.split(".")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("expected MAJOR.MINOR.PATCH")
    major, minor, patch = (int(part) for part in parts)
    if not (0 <= major <= 0x7F and 0 <= minor <= 0x7F and 0 <= patch <= 0x7F):
        raise argparse.ArgumentTypeError("os_version components must be 0..127")
    return (major << 14) | (minor << 7) | patch


def parse_os_patch_level(value):
    try:
        year_s, month_s = value.split("-", 1)
        year = int(year_s)
        month = int(month_s)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected YYYY-MM") from exc
    if not (2000 <= year <= 2127 and 1 <= month <= 12):
        raise argparse.ArgumentTypeError("os_patch_level must be YYYY-MM")
    return ((year - 2000) << 4) | month


def encode_os_version_patch(os_version, os_patch_level):
    return (os_version << 11) | os_patch_level


def read_file(path):
    with open(path, "rb") as handle:
        return handle.read()


def pad_file(handle, page_size):
    position = handle.tell()
    padding = (-position) % page_size
    if padding:
        handle.write(b"\0" * padding)


def fixed_bytes(value, size, field_name):
    data = value.encode("utf-8")
    if len(data) > size:
        raise SystemExit(f"ERROR: {field_name} is too long ({len(data)} > {size})")
    return data + b"\0" * (size - len(data))


def split_cmdline(cmdline):
    data = cmdline.encode("utf-8")
    if len(data) > BOOT_ARGS_SIZE + BOOT_EXTRA_ARGS_SIZE:
        raise SystemExit(
            "ERROR: cmdline is too long "
            f"({len(data)} > {BOOT_ARGS_SIZE + BOOT_EXTRA_ARGS_SIZE})"
        )
    first = data[:BOOT_ARGS_SIZE]
    extra = data[BOOT_ARGS_SIZE:]
    return (
        first + b"\0" * (BOOT_ARGS_SIZE - len(first)),
        extra + b"\0" * (BOOT_EXTRA_ARGS_SIZE - len(extra)),
    )


def build_boot_id(chunks):
    digest = hashlib.sha1()
    for chunk in chunks:
        digest.update(chunk)
        digest.update(struct.pack("<I", len(chunk)))
    return digest.digest() + b"\0" * (BOOT_ID_SIZE - hashlib.sha1().digest_size)


def main():
    parser = argparse.ArgumentParser(description="Create an Android boot image")
    parser.add_argument("--kernel", required=True)
    parser.add_argument("--ramdisk", required=True)
    parser.add_argument("--base", type=parse_int, default=0)
    parser.add_argument("--kernel_offset", type=parse_int, default=0x00008000)
    parser.add_argument("--ramdisk_offset", type=parse_int, default=0x01000000)
    parser.add_argument("--second_offset", type=parse_int, default=0x00F00000)
    parser.add_argument("--tags_offset", type=parse_int, default=0x00000100)
    parser.add_argument("--pagesize", type=parse_int, default=2048)
    parser.add_argument("--header_version", type=int, default=0)
    parser.add_argument("--cmdline", default="")
    parser.add_argument("--name", default="")
    parser.add_argument("--os_version", type=parse_os_version, default=0)
    parser.add_argument("--os_patch_level", type=parse_os_patch_level, default=0)
    parser.add_argument("-o", "--output", required=True)
    args = parser.parse_args()

    if args.header_version not in (0, 1):
        raise SystemExit("ERROR: this project-local mkbootimg supports header_version 0 or 1")
    if args.pagesize <= 0 or args.pagesize & (args.pagesize - 1):
        raise SystemExit("ERROR: pagesize must be a positive power of two")

    kernel = read_file(args.kernel)
    ramdisk = read_file(args.ramdisk)
    cmdline, extra_cmdline = split_cmdline(args.cmdline)

    header_version = args.header_version
    header_size = 1648 if header_version == 1 else 1632
    os_version_patch = encode_os_version_patch(args.os_version, args.os_patch_level)

    header = struct.pack(
        "<8s10I16s512s32s1024s",
        BOOT_MAGIC,
        len(kernel),
        args.base + args.kernel_offset,
        len(ramdisk),
        args.base + args.ramdisk_offset,
        0,
        args.base + args.second_offset,
        args.base + args.tags_offset,
        args.pagesize,
        header_version,
        os_version_patch,
        fixed_bytes(args.name, BOOT_NAME_SIZE, "name"),
        cmdline,
        build_boot_id((kernel, ramdisk)),
        extra_cmdline,
    )

    if header_version == 1:
        header += struct.pack("<IQI", 0, 0, header_size)

    if len(header) != header_size:
        raise AssertionError(f"header size mismatch: {len(header)} != {header_size}")

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as output:
        output.write(header)
        pad_file(output, args.pagesize)
        output.write(kernel)
        pad_file(output, args.pagesize)
        output.write(ramdisk)
        pad_file(output, args.pagesize)


if __name__ == "__main__":
    sys.exit(main())
