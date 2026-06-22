#!/bin/bash
# Compatibility entrypoint. Build support logic lives in scripts/register-binfmt.sh.
set -euo pipefail
exec bash /mnt/c/repo/razorphone2linux/scripts/register-binfmt.sh "$@"
