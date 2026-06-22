#!/bin/bash
# Compatibility entrypoint. Build logic lives in scripts/03-build-rootfs.sh.
set -euo pipefail
if [ "$EUID" -eq 0 ]; then
    exec bash /mnt/c/repo/razorphone2linux/scripts/03-build-rootfs.sh "$@"
fi
exec sudo bash /mnt/c/repo/razorphone2linux/scripts/03-build-rootfs.sh "$@"
