#!/bin/bash
# Compatibility entrypoint. Build logic lives in scripts/02-build-kernel.sh.
set -euo pipefail
exec bash /mnt/c/repo/razorphone2linux/scripts/02-build-kernel.sh "$@"
