#!/bin/bash
set -euo pipefail

: "${CHROOT_DIR:?}"
: "${PROJECT_DIR:?}"

cp -f "$PROJECT_DIR/rootfs-scripts/install-final-target.sh" "$CHROOT_DIR/tmp/install-final-target.sh"
cp -f "$PROJECT_DIR/config/userspace.env" "$CHROOT_DIR/tmp/userspace.env"
chmod +x "$CHROOT_DIR/tmp/install-final-target.sh"

chroot "$CHROOT_DIR" /usr/bin/env \
    PIP_INDEX_URL=https://pypi.org/simple \
    PIP_CACHE_DIR=/var/cache/razer-pip \
    /tmp/install-final-target.sh

chroot "$CHROOT_DIR" /bin/sh -c \
    'pkill -x helix-watchdog 2>/dev/null || true; pkill -x helix-screen 2>/dev/null || true; pkill -x helix-splash 2>/dev/null || true'
