#!/bin/bash
# Install CI host packages reliably on GitHub's ARM64 runners.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: ci-apt-install.sh must run as root." >&2
    exit 1
fi
if [ "$#" -eq 0 ]; then
    echo "ERROR: no packages requested." >&2
    exit 2
fi

# The hosted ARM64 image has occasionally advertised unreachable IPv6 routes
# and still carried an HTTP Ubuntu Ports URI. HTTPS plus IPv4 avoids waiting
# through several connection timeouts before each retry.
find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -print0 |
    xargs -0 -r sed -i \
        's|http://ports\.ubuntu\.com/ubuntu-ports|https://ports.ubuntu.com/ubuntu-ports|g'

APT_OPTIONS=(
    -o Acquire::ForceIPv4=true
    -o Acquire::Retries=5
    -o Acquire::http::Timeout=30
    -o Acquire::https::Timeout=30
)

for attempt in 1 2 3; do
    if apt-get "${APT_OPTIONS[@]}" update &&
            DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTIONS[@]}" \
                install -y --no-install-recommends "$@"; then
        exit 0
    fi
    if [ "$attempt" -eq 3 ]; then
        echo "ERROR: apt installation failed after $attempt attempts." >&2
        exit 1
    fi
    echo "APT attempt $attempt failed; retrying..." >&2
    sleep $((attempt * 10))
done
