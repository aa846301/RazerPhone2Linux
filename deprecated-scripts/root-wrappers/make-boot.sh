#!/bin/bash
# Compatibility entrypoint. Build logic lives in scripts/04-make-boot-image.sh.
set -euo pipefail
exec bash /mnt/c/repo/razorphone2linux/scripts/04-make-boot-image.sh "$@"
