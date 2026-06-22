#!/usr/bin/env python3
"""
Create a minimal but valid AVB2 vbmeta image with all verification disabled.

AVB2 AvbVBMetaImageHeader is exactly 256 bytes, big-endian packed.
Flags: HASHTREE_DISABLED (bit 0) | VERIFICATION_DISABLED (bit 1) = 3

Usage:
    python3 make-vbmeta-disabled.py [output_path]

Default output: /mnt/c/repo/razorphone2linux/output/vbmeta_disabled.img
"""

import struct
import sys
import os

OUTPUT = (
    sys.argv[1]
    if len(sys.argv) > 1
    else "/mnt/c/repo/razorphone2linux/output/vbmeta_disabled.img"
)

# AvbVBMetaImageHeader – 256 bytes, all big-endian
# Ref: external/avb/libavb/avb_vbmeta_image.h in AOSP
#
# Offset  Size  Field
#      0     4  magic = "AVB0"
#      4     4  required_libavb_version_major
#      8     4  required_libavb_version_minor
#     12     8  authentication_data_block_size
#     20     8  auxiliary_data_block_size
#     28     4  algorithm_type  (0 = NONE)
#     32     8  hash_offset
#     40     8  hash_size
#     48     8  signature_offset
#     56     8  signature_size
#     64     8  public_key_offset
#     72     8  public_key_size
#     80     8  public_key_metadata_offset
#     88     8  public_key_metadata_size
#     96     8  descriptors_offset
#    104     8  descriptors_size
#    112     8  rollback_index
#    120     4  flags
#    124     4  rollback_index_location
#    128    48  release_string
#    176    80  reserved
#    256  (total)

AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED    = 1 << 0  # 1
AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED = 1 << 1  # 2
FLAGS_ALL_DISABLED = (
    AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED
    | AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED
)  # 3

RELEASE = b"avbtool 1.1.0\x00"
RELEASE = RELEASE + b"\x00" * (48 - len(RELEASE))  # pad to 48 bytes

FMT = ">4sIIQQIQQQQQQQQQQQII48s80s"

header = struct.pack(
    FMT,
    b"AVB0",          # magic
    1,                # required_libavb_version_major
    2,                # required_libavb_version_minor
    0,                # authentication_data_block_size
    0,                # auxiliary_data_block_size
    0,                # algorithm_type = NONE
    0,                # hash_offset
    0,                # hash_size
    0,                # signature_offset
    0,                # signature_size
    0,                # public_key_offset
    0,                # public_key_size
    0,                # public_key_metadata_offset
    0,                # public_key_metadata_size
    0,                # descriptors_offset
    0,                # descriptors_size
    0,                # rollback_index
    FLAGS_ALL_DISABLED,  # flags = 3
    0,                # rollback_index_location
    RELEASE,          # release_string[48]
    b"\x00" * 80,     # reserved[80]
)

assert len(header) == 256, f"BUG: header is {len(header)} bytes, expected 256"
assert header[:4] == b"AVB0", "BUG: magic not written correctly"

os.makedirs(os.path.dirname(os.path.abspath(OUTPUT)), exist_ok=True)
with open(OUTPUT, "wb") as f:
    f.write(header)

print(f"[ok] Created: {OUTPUT}")
print(f"     Size   : {len(header)} bytes")
print(f"     Magic  : {header[:4]}")
print(f"     Flags  : {FLAGS_ALL_DISABLED} (HASHTREE_DISABLED | VERIFICATION_DISABLED)")
