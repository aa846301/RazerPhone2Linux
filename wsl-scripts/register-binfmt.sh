#!/bin/bash
# Register aarch64 binfmt_misc for qemu
set -e
mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
# Using printf to avoid shell escaping issues
printf '%s' ':qemu-aarch64:M:0:\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:CF' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    cat /proc/sys/fs/binfmt_misc/qemu-aarch64
    echo "BINFMT_OK"
else
    echo "BINFMT_FAIL"
fi
