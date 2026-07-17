#!/usr/bin/env bash
set -euo pipefail

SRC_TAR="${1:-/tmp/rmtfs-detail-source.tar.gz}"
OUT_BIN="${2:-/tmp/rmtfs-detail}"
WORK_DIR="${RMTFS_DETAIL_WORK_DIR:-/tmp/rmtfs-detail-build}"
SYSROOT="$WORK_DIR/sysroot"
SRC_DIR="$WORK_DIR/src"

if [ ! -f "$SRC_TAR" ]; then
	echo "missing source tar: $SRC_TAR" >&2
	exit 2
fi

shopt -s nullglob
DEBS=(/tmp/libqrtr-dev_*_arm64.deb /tmp/libudev-dev_*_arm64.deb)
shopt -u nullglob

if [ "${#DEBS[@]}" -lt 2 ]; then
	echo "missing arm64 dev debs in /tmp: libqrtr-dev and libudev-dev" >&2
	exit 2
fi

rm -rf "$WORK_DIR"
mkdir -p "$SYSROOT" "$SRC_DIR"

for deb in "${DEBS[@]}"; do
	dpkg-deb -x "$deb" "$SYSROOT"
done

LIBDIR="$SYSROOT/usr/lib/aarch64-linux-gnu"
for lib in libqrtr.so.1 libudev.so.1; do
	if [ ! -e "$LIBDIR/$lib" ] && [ -e "/usr/lib/aarch64-linux-gnu/$lib" ]; then
		ln -s "/usr/lib/aarch64-linux-gnu/$lib" "$LIBDIR/$lib"
	fi
done

tar -xzf "$SRC_TAR" -C "$SRC_DIR"

cd "$SRC_DIR"
make clean >/dev/null 2>&1 || true
make \
	CC="${CC:-cc}" \
	CFLAGS="-Wall -g -O2 -I$SYSROOT/usr/include" \
	LDFLAGS="-L$SYSROOT/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$SYSROOT/usr/lib/aarch64-linux-gnu -lqrtr -ludev -lpthread" \
	rmtfs

install -m 0755 rmtfs "$OUT_BIN"
sha256sum "$OUT_BIN"
ls -l "$OUT_BIN"
