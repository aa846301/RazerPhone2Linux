#!/bin/bash
# Build ONLY sound/soc/qcom/snd-soc-sdm845.ko so it drops into the kernel already running on the phone, without
# rebuilding or reflashing the kernel.
#
# Why this is ABI-safe here: the running kernel has CONFIG_MODVERSIONS=n, CONFIG_MODULE_SIG=n and
# CONFIG_LOCALVERSION_AUTO=n, so the loader only checks vermagic ("7.1.0-rc1-sdm845 SMP preempt mod_unload
# aarch64"), which a rebuild reproduces. Struct layouts must still match, so the tree is the repository's
# kernel-source/linux + every kernel-patches/*.patch that touches sound/soc/qcom/sdm845.c (0008, 0016; the other
# patches do not touch this module or the headers it uses), configured with the phone's own /proc/config.gz.
#
# Usage (WSL): build-sdm845-sndcard-module.sh <phone-config> [out-dir]
set -euo pipefail
PHONE_CONFIG=$(readlink -f "$1")
REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${2:-$REPO/output/sndcard-module}
W=${KBUILD_WORK:-$HOME/kbuild-sndcard}
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=""

mkdir -p "$W" "$OUT"
# Export the committed tree straight from git: a Windows working copy is CRLF-converted (Kconfig breaks), while
# git stores the LF content CI built from. kernel-source/ has no uncommitted changes when this is used.
echo "== export kernel-source/linux from git HEAD -> $W/linux"
# (Check for uncommitted kernel-source changes on the Windows side: `git status` over /mnt/d takes >15 min.)
rm -rf "$W/linux" && mkdir -p "$W/linux"
git -C "$REPO" -c core.autocrlf=false archive HEAD:kernel-source/linux | tar -x -C "$W/linux"
cd "$W/linux"
grep -c $'\r' Kconfig >/dev/null && { echo "ERROR: exported tree still has CRLF"; exit 1; } || true
for p in "$REPO"/kernel-patches/*.patch; do
    grep -qE '^\+\+\+ b/sound/soc/(qcom/sdm845\.c|codecs/tfa98xx-downstream/)' "$p" || continue
    echo "== apply $(basename "$p")"
    sed 's/\r$//' "$p" | patch -p1 --forward --no-backup-if-mismatch   # patch files may be CRLF on Windows
done

echo "== config from the phone"
cp "$PHONE_CONFIG" .config
make -s olddefconfig
diff <(grep -v '^#' "$PHONE_CONFIG" | grep . | sort) <(grep -v '^#' .config | grep . | sort) | grep '^[<>]' \
    | grep -vE 'CONFIG_(CC_VERSION_TEXT|GCC_VERSION|RUSTC_|RUST_|BINDGEN_|LD_VERSION|AS_VERSION|PAHOLE_)' \
    && { echo "ERROR: config differs from the phone beyond toolchain lines"; exit 1; } || true
echo "kernel release: $(make -s kernelrelease)"

echo "== modules_prepare + modules"
make -s -j"$(nproc)" modules_prepare
for ko in sound/soc/qcom/snd-soc-sdm845.ko sound/soc/codecs/snd-soc-tfa98xx.ko; do
    rm -f "$ko"
    KBUILD_MODPOST_WARN=1 make -j"$(nproc)" "$ko" 2>&1 | grep -E 'error|warning:' || true
    [ -f "$ko" ] || { echo "ERROR: $ko not built"; exit 1; }
    install -m 0644 "$ko" "$OUT/"
    aarch64-linux-gnu-strip --strip-debug "$OUT/$(basename "$ko")"
    modinfo "$OUT/$(basename "$ko")" | grep -E '^(name|vermagic|depends)'
    sha256sum "$OUT/$(basename "$ko")"
done
