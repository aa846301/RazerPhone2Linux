#!/usr/bin/env python3
import struct, os

path = os.path.expanduser('~/razorphone2linux/output/Image.gz-dtb')
data = open(path, 'rb').read()

magic = struct.pack('>I', 0xd00dfeed)
idx = data.rfind(magic)
if idx >= 0:
    print(f'DTB found at offset {idx} (0x{idx:x})')
    print(f'Total file size: {len(data)} bytes')
    print(f'DTB size: {len(data) - idx} bytes')
    # Check DTB totalsize field (bytes 4-7 in DTB header)
    dtb_totalsize = struct.unpack('>I', data[idx+4:idx+8])[0]
    print(f'DTB header totalsize: {dtb_totalsize} bytes')
    if dtb_totalsize == len(data) - idx:
        print('DTB size matches! This is a single DTB append.')
    else:
        print(f'Size mismatch - multiple DTBs or padding?')
else:
    print('DTB magic NOT found in Image.gz-dtb')
