#!/bin/bash
# Extract split Qualcomm firmware from the stock Razer Phone 2 modem.img into
# the repo firmware tree used by scripts/03-build-rootfs.sh.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_MODEM_IMG="$PROJECT_DIR/aura-p-release-3201-user-full/aura-p-release-3201/modem.img"
DEFAULT_FACTORY_ZIP="$PROJECT_DIR/aura-p-release-3201-user-full.zip"
SOURCE="${1:-$DEFAULT_MODEM_IMG}"
DEST_DIR="$PROJECT_DIR/firmware/qcom/sdm845/Razer/aura"
ATH10K_DIR="$PROJECT_DIR/firmware/ath10k/WCN3990/hw1.0"

if ! command -v 7z >/dev/null 2>&1; then
    echo "ERROR: 7z is required to extract FAT modem.img"
    exit 1
fi

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT

if [ -f "$SOURCE" ] && [[ "$SOURCE" == *.zip ]]; then
    echo "Extracting modem.img from factory package: $SOURCE"
    7z e -y -o"$tmpdir/factory" "$SOURCE" 'aura-p-release-3201/modem.img' >/dev/null
    MODEM_IMG="$tmpdir/factory/modem.img"
elif [ -f "$SOURCE" ]; then
    MODEM_IMG="$SOURCE"
elif [ -f "$DEFAULT_FACTORY_ZIP" ]; then
    echo "Extracting modem.img from factory package: $DEFAULT_FACTORY_ZIP"
    7z e -y -o"$tmpdir/factory" "$DEFAULT_FACTORY_ZIP" \
        'aura-p-release-3201/modem.img' >/dev/null
    MODEM_IMG="$tmpdir/factory/modem.img"
else
    echo "ERROR: no modem image or factory ZIP found."
    echo "Expected one of:"
    echo "  $SOURCE"
    echo "  $DEFAULT_FACTORY_ZIP"
    exit 1
fi

if [ ! -f "$MODEM_IMG" ]; then
    echo "ERROR: modem.img was not extracted from $SOURCE"
    exit 1
fi

mkdir -p "$DEST_DIR" "$ATH10K_DIR"

echo "Extracting modem firmware from: $MODEM_IMG"
if ! 7z x -y -o"$tmpdir" "$MODEM_IMG" 'image/*' >/tmp/razer-modem-7z.log; then
    # Razer's FAT modem image reports a larger physical size than the sparse
    # factory file, so 7z exits non-zero after extracting usable files.
    if ! find "$tmpdir/image" -type f -name 'modem.mdt' >/dev/null 2>&1; then
        cat /tmp/razer-modem-7z.log
        echo "ERROR: 7z did not extract modem firmware"
        exit 1
    fi
    echo "  7z reported a FAT size warning; continuing with extracted files."
fi

copy_family() {
    local family="$1"
    local header_src="$tmpdir/image/$family.mdt"
    local header_dst="$DEST_DIR/$family.mbn"

    if [ ! -f "$header_src" ]; then
        echo "WARNING: missing image/$family.mdt"
        return 0
    fi

    cp -f "$header_src" "$header_dst"
    find "$tmpdir/image" -maxdepth 1 -type f -name "$family.b[0-9][0-9]" -print0 |
        while IFS= read -r -d '' segment; do
            cp -f "$segment" "$DEST_DIR/$(basename "$segment")"
        done
    echo "  $family: header + $(find "$DEST_DIR" -maxdepth 1 -type f -name "$family.b[0-9][0-9]" | wc -l) segments"
}

for family in adsp cdsp modem slpi venus; do
    copy_family "$family"
done

if [ -f "$tmpdir/image/mba.mbn" ]; then
    cp -f "$tmpdir/image/mba.mbn" "$DEST_DIR/mba.mbn"
fi

if [ -f "$tmpdir/image/wlanmdsp.mbn" ]; then
    cp -f "$tmpdir/image/wlanmdsp.mbn" "$DEST_DIR/wlanmdsp.mbn"
fi

for file in ipa_fws.mbn modemr.jsn modemuw.jsn; do
    if [ -f "$tmpdir/image/$file" ]; then
        cp -f "$tmpdir/image/$file" "$DEST_DIR/$file"
    fi
done

# Preserve the Razer board-data family. The DTS calibration variant selects
# the matching entry from board-2.bin; board.bin is the fallback used by older
# ath10k loaders.
find "$tmpdir/image" -maxdepth 1 -type f -name 'bdwlan*' -print0 |
    while IFS= read -r -d '' board_file; do
        cp -f "$board_file" "$ATH10K_DIR/$(basename "$board_file")"
    done
if [ -f "$ATH10K_DIR/bdwlan.bin" ]; then
    cp -f "$ATH10K_DIR/bdwlan.bin" "$ATH10K_DIR/board.bin"
fi

echo "Firmware output:"
find "$DEST_DIR" -maxdepth 1 -type f -printf '  %f %s bytes\n' | sort
find "$ATH10K_DIR" -maxdepth 1 -type f -printf '  ath10k/%f %s bytes\n' | sort
