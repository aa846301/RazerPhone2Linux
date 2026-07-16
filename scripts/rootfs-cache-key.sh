#!/bin/bash
# Compute the reusable rootfs base-image cache key. Kernel modules, firmware,
# runtime overlays, and initramfs are applied later by 03-refresh-rootfs.sh.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_PROFILE="${RAZER_IMAGE_PROFILE:-base}"
USERSPACE_PROFILE="${RAZER_USERSPACE_PROFILE:-none}"
CACHE_VERSION="${RAZER_ROOTFS_CACHE_VERSION:-1}"
RUNNER_OS_VALUE="${RUNNER_OS:-Linux}"
RUNNER_ARCH_VALUE="${RUNNER_ARCH:-ARM64}"

input_hash="$({
    printf 'cache_version=%s\n' "$CACHE_VERSION"
    printf 'image_profile=%s\n' "$IMAGE_PROFILE"
    printf 'userspace_profile=%s\n' "$USERSPACE_PROFILE"
    printf 'ubuntu_mirror=%s\n' \
        "${RAZER_UBUNTU_MIRROR:-https://ports.ubuntu.com/ubuntu-ports}"
    git -C "$PROJECT_DIR" ls-files -s -- \
        config/build.env \
        config/userspace.env \
        scripts/03-build-rootfs.sh \
        rootfs-packages/arm64 \
        rootfs-scripts/install-final-target.sh \
        rootfs-scripts/kiosk-prototype \
        "rootfs-profiles/$USERSPACE_PROFILE"
} | sha256sum | cut -d' ' -f1)"

printf 'rootfs-%s-%s-%s-%s-%s\n' \
    "$RUNNER_OS_VALUE" "$RUNNER_ARCH_VALUE" "$IMAGE_PROFILE" \
    "$USERSPACE_PROFILE" "$input_hash"
