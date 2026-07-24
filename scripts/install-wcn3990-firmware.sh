#!/bin/bash
# Install the mainline ath10k API file needed by the WCN3990 SNOC driver.
#
# Factory modem firmware supplies Razer-specific board/calibration data, but it
# does not contain firmware-5.bin. Keep this helper shared by full rootfs builds,
# cached-rootfs refreshes, and CI firmware-cache creation so no path can omit it.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <firmware-root>" >&2
    exit 2
fi

FIRMWARE_ROOT="$1"
ATH10K_DIR="$FIRMWARE_ROOT/ath10k/WCN3990/hw1.0"
ALLOW_MISSING="${RAZER_ALLOW_MISSING_FIRMWARE:-0}"
LINUX_FIRMWARE_COMMIT="${WCN3990_LINUX_FIRMWARE_COMMIT:-b142c2e0229bc89b44ac527f4f3c3def063bcbc6}"
FIRMWARE5_SHA256="${WCN3990_FIRMWARE5_SHA256:-fef6539e0127579536bc977be57a90d018b83f2931fedc3a8870fbe38d6c4127}"
FIRMWARE5_URL="${WCN3990_FIRMWARE5_URL:-https://gitlab.com/kernel-firmware/linux-firmware/-/raw/${LINUX_FIRMWARE_COMMIT}/ath10k/WCN3990/hw1.0/firmware-5.bin}"
FIRMWARE5_PATH="$ATH10K_DIR/firmware-5.bin"

mkdir -p "$ATH10K_DIR"

firmware5_is_valid() {
    local path="$1"
    local actual_sha256

    [ -s "$path" ] || return 1
    actual_sha256="$(sha256sum "$path" | cut -d' ' -f1)"
    [ "$actual_sha256" = "$FIRMWARE5_SHA256" ]
}

fail_or_allow() {
    local message="$1"

    if [ "$ALLOW_MISSING" = "1" ]; then
        echo "WARNING: $message" >&2
        echo "WARNING: RAZER_ALLOW_MISSING_FIRMWARE=1; continuing without working WiFi." >&2
        return 0
    fi

    echo "ERROR: $message" >&2
    return 1
}

if firmware5_is_valid "$FIRMWARE5_PATH"; then
    echo "  Keeping verified WCN3990 firmware-5.bin ($(stat -c %s "$FIRMWARE5_PATH") bytes)."
else
    tmp_file="$(mktemp "$ATH10K_DIR/.firmware-5.bin.XXXXXX")"
    cleanup() {
        rm -f "$tmp_file"
    }
    trap cleanup EXIT

    echo "  Downloading pinned WCN3990 firmware-5.bin from linux-firmware..."
    if command -v curl >/dev/null 2>&1; then
        if ! curl -L --fail --retry 3 --retry-all-errors \
                -o "$tmp_file" "$FIRMWARE5_URL"; then
            fail_or_allow "failed to download WCN3990 firmware-5.bin from $FIRMWARE5_URL"
            exit $?
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --timeout=30 -O "$tmp_file" "$FIRMWARE5_URL"; then
            fail_or_allow "failed to download WCN3990 firmware-5.bin from $FIRMWARE5_URL"
            exit $?
        fi
    else
        fail_or_allow "curl or wget is required to install WCN3990 firmware-5.bin"
        exit $?
    fi

    if ! firmware5_is_valid "$tmp_file"; then
        actual_sha256="$(sha256sum "$tmp_file" | cut -d' ' -f1)"
        fail_or_allow "WCN3990 firmware-5.bin checksum mismatch (expected $FIRMWARE5_SHA256, got $actual_sha256)"
        exit $?
    fi

    install -m 0644 "$tmp_file" "$FIRMWARE5_PATH"
    echo "  Installed verified WCN3990 firmware-5.bin ($(stat -c %s "$FIRMWARE5_PATH") bytes)."
fi

if [ ! -s "$ATH10K_DIR/board-2.bin" ] && [ ! -s "$ATH10K_DIR/board.bin" ]; then
    fail_or_allow "WCN3990 board data is missing from $ATH10K_DIR (expected board-2.bin or board.bin)"
    exit $?
fi

echo "  WCN3990 firmware requirements verified."
