#!/bin/bash
# Compatibility entrypoint. Build logic lives in scripts/build-all.sh.
set -euo pipefail
exec bash /mnt/c/repo/razorphone2linux/scripts/build-all.sh all
