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
QCA_DIR="$PROJECT_DIR/firmware/qca"
TFA_CNT="$PROJECT_DIR/firmware/tfa98xx.cnt"
FACTORY_ZIP=""

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
    FACTORY_ZIP="$SOURCE"
    modem_entry="$({
        7z l -slt "$SOURCE" |
            awk -F' = ' '/^Path = / {
                path = $2
                gsub(/\\/, "/", path)
                if (path ~ /(^|\/)modem\.img$/) {
                    print path
                    exit
                }
            }'
    })"
    if [ -z "$modem_entry" ]; then
        echo "ERROR: modem.img was not found inside $SOURCE"
        exit 1
    fi
    7z e -y -o"$tmpdir/factory" "$SOURCE" "$modem_entry" >/dev/null
    MODEM_IMG="$tmpdir/factory/modem.img"
elif [ -f "$SOURCE" ]; then
    MODEM_IMG="$SOURCE"
elif [ -f "$DEFAULT_FACTORY_ZIP" ]; then
    echo "Extracting modem.img from factory package: $DEFAULT_FACTORY_ZIP"
    FACTORY_ZIP="$DEFAULT_FACTORY_ZIP"
    modem_entry="$({
        7z l -slt "$DEFAULT_FACTORY_ZIP" |
            awk -F' = ' '/^Path = / {
                path = $2
                gsub(/\\/, "/", path)
                if (path ~ /(^|\/)modem\.img$/) {
                    print path
                    exit
                }
            }'
    })"
    if [ -z "$modem_entry" ]; then
        echo "ERROR: modem.img was not found inside $DEFAULT_FACTORY_ZIP"
        exit 1
    fi
    7z e -y -o"$tmpdir/factory" "$DEFAULT_FACTORY_ZIP" "$modem_entry" >/dev/null
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

if [ -n "$FACTORY_ZIP" ]; then
    for tool in file mcopy debugfs simg2img; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "ERROR: $tool is required to extract bluetooth.img"
            exit 1
        fi
    done

    bluetooth_entry="$({
        7z l -slt "$FACTORY_ZIP" |
            awk -F' = ' '/^Path = / {
                path = $2
                gsub(/\\/, "/", path)
                if (path ~ /(^|\/)bluetooth\.img$/) {
                    print path
                    exit
                }
            }'
    })"
    if [ -z "$bluetooth_entry" ]; then
        echo "ERROR: bluetooth.img was not found inside $FACTORY_ZIP"
        exit 1
    fi

    mkdir -p "$tmpdir/bluetooth" "$tmpdir/bluetooth-fs"
    7z e -y -o"$tmpdir/bluetooth" "$FACTORY_ZIP" "$bluetooth_entry" >/dev/null
    bluetooth_img="$tmpdir/bluetooth/bluetooth.img"
    bluetooth_raw="$tmpdir/bluetooth.raw.img"
    image_type="$(file -b "$bluetooth_img")"
    if [[ "$image_type" == *"Android sparse image"* ]]; then
        simg2img "$bluetooth_img" "$bluetooth_raw"
    else
        cp -f "$bluetooth_img" "$bluetooth_raw"
    fi

    raw_type="$(file -b "$bluetooth_raw")"
    echo "Bluetooth firmware image type: $raw_type"
    if [[ "$raw_type" == *"FAT"* ]]; then
        mcopy -i "$bluetooth_raw" -s '::*' "$tmpdir/bluetooth-fs/"
    elif [[ "$raw_type" == *"ext2 filesystem"* ]] ||
            [[ "$raw_type" == *"ext3 filesystem"* ]] ||
            [[ "$raw_type" == *"ext4 filesystem"* ]]; then
        debugfs -R "rdump / $tmpdir/bluetooth-fs" "$bluetooth_raw"
    else
        echo "ERROR: unsupported bluetooth.img filesystem: $raw_type"
        exit 1
    fi

    tlv_src="$(find "$tmpdir/bluetooth-fs" -type f -iname crbtfw21.tlv -print -quit)"
    nvm_src="$(find "$tmpdir/bluetooth-fs" -type f -iname crnv21.bin -print -quit)"
    if [ -z "$tlv_src" ] || [ -z "$nvm_src" ]; then
        echo "ERROR: WCN3990 firmware was not found in bluetooth.img"
        exit 1
    fi
    install -D -m 0644 "$tlv_src" "$QCA_DIR/crbtfw21.tlv"
    install -D -m 0644 "$nvm_src" "$QCA_DIR/crnv21.bin"
    install -D -m 0644 "$nvm_src" "$QCA_DIR/Razer/aura/crnv21.bin"

    vendor_entry="$({
        7z l -slt "$FACTORY_ZIP" |
            awk -F' = ' '/^Path = / {
                path = $2
                gsub(/\\/, "/", path)
                if (path ~ /(^|\/)vendor\.img$/) {
                    print path
                    exit
                }
            }'
    })"
    if [ -z "$vendor_entry" ]; then
        echo "ERROR: vendor.img was not found inside $FACTORY_ZIP"
        exit 1
    fi

    mkdir -p "$tmpdir/vendor"
    7z e -y -o"$tmpdir/vendor" "$FACTORY_ZIP" "$vendor_entry" >/dev/null
    vendor_img="$tmpdir/vendor/vendor.img"
    vendor_raw="$tmpdir/vendor.raw.img"
    image_type="$(file -b "$vendor_img")"
    if [[ "$image_type" == *"Android sparse image"* ]]; then
        simg2img "$vendor_img" "$vendor_raw"
    else
        cp -f "$vendor_img" "$vendor_raw"
    fi

    raw_type="$(file -b "$vendor_raw")"
    echo "Vendor firmware image type: $raw_type"
    if [[ "$raw_type" != *"ext2 filesystem"* ]] &&
            [[ "$raw_type" != *"ext3 filesystem"* ]] &&
            [[ "$raw_type" != *"ext4 filesystem"* ]]; then
        echo "ERROR: unsupported vendor.img filesystem: $raw_type"
        exit 1
    fi

    debugfs -R "dump /firmware/tfa98xx.cnt $tmpdir/tfa98xx.cnt" "$vendor_raw"
    if [ ! -s "$tmpdir/tfa98xx.cnt" ]; then
        echo "ERROR: /firmware/tfa98xx.cnt was not found in vendor.img"
        exit 1
    fi
    install -D -m 0644 "$tmpdir/tfa98xx.cnt" "$TFA_CNT"
    echo "  tfa98xx.cnt: $(stat -c %s "$TFA_CNT") bytes"
else
    echo "WARNING: a factory ZIP is required to extract tfa98xx.cnt"
fi

echo "Firmware output:"
find "$DEST_DIR" -maxdepth 1 -type f -printf '  %f %s bytes\n' | sort
find "$ATH10K_DIR" -maxdepth 1 -type f -printf '  ath10k/%f %s bytes\n' | sort
if [ -d "$QCA_DIR" ]; then
    find "$QCA_DIR" -type f -printf '  qca/%P %s bytes\n' | sort
fi
if [ -f "$TFA_CNT" ]; then
    find "$TFA_CNT" -maxdepth 0 -type f -printf '  %f %s bytes\n'
fi
