#!/bin/bash
# Compatibility dispatcher for old WSL/home entrypoints.
# Keep build logic in scripts/02-build-kernel.sh, 03-build-rootfs.sh,
# 04-make-boot-image.sh, and scripts/build-all.sh only.

set -euo pipefail

WIN_REPO="${WIN_REPO:-/mnt/c/repo/razorphone2linux}"
name="$(basename "$0")"

case "$name" in
    rebuild-kernel.sh|wsl-build-kernel.sh)
        exec bash "$WIN_REPO/scripts/02-build-kernel.sh" "$@"
        ;;
    make-rootfs.sh)
        if [ "$EUID" -eq 0 ]; then
            exec bash "$WIN_REPO/scripts/03-build-rootfs.sh" "$@"
        fi
        exec sudo bash "$WIN_REPO/scripts/03-build-rootfs.sh" "$@"
        ;;
    make-boot.sh)
        exec bash "$WIN_REPO/scripts/04-make-boot-image.sh" "$@"
        ;;
    full-build.sh|rebuild-all.sh)
        exec bash "$WIN_REPO/scripts/build-all.sh" all
        ;;
    *)
        echo "ERROR: unknown compatibility entrypoint: $name"
        exit 2
        ;;
esac
