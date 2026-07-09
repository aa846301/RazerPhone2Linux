#!/bin/bash
set -euo pipefail

IDLE_SECONDS="${RAZER_PANEL_IDLE_SECONDS:-60}"
sleep "$IDLE_SECONDS"

if [ -w /sys/class/graphics/fb0/blank ]; then
    echo 1 > /sys/class/graphics/fb0/blank || true
fi

for dpms in /sys/class/drm/*/dpms; do
    [ -w "$dpms" ] || continue
    echo Off > "$dpms" || true
done
