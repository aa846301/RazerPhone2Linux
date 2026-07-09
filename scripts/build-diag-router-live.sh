#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$REPO_ROOT/.tmp"
DIAG_DIR="$TMP_DIR/diag"
QRTR_DIR="$TMP_DIR/qrtr"
OUT_DIR="$REPO_ROOT/output/diag-router-live"

mkdir -p "$TMP_DIR" "$OUT_DIR"

if [ ! -d "$QRTR_DIR/.git" ]; then
    git clone https://github.com/andersson/qrtr.git "$QRTR_DIR"
fi

if [ ! -d "$DIAG_DIR/.git" ]; then
    git clone https://github.com/andersson/diag.git "$DIAG_DIR"
fi

cd "$QRTR_DIR"
rm -f lib/*.o libqrtr.a
aarch64-linux-gnu-gcc -Wall -O2 -Iinclude -c lib/logging.c -o lib/logging.o
aarch64-linux-gnu-gcc -Wall -O2 -Iinclude -c lib/qmi.c -o lib/qmi.o
aarch64-linux-gnu-gcc -Wall -O2 -Iinclude -c lib/qrtr.c -o lib/qrtr.o
aarch64-linux-gnu-ar rcs libqrtr.a lib/logging.o lib/qmi.o lib/qrtr.o

cd "$DIAG_DIR"
git checkout -- router/diag.c router/diag_cntl.c
git apply "$REPO_ROOT/tools/diag-router-qrtr-only.patch"
make clean
make \
    CC=aarch64-linux-gnu-gcc \
    HAVE_LIBUDEV=0 \
    HAVE_LIBQRTR=1 \
    CFLAGS="-Wall -O2 -I$QRTR_DIR/include -DHAS_LIBQRTR=1" \
    LDFLAGS="$QRTR_DIR/libqrtr.a" \
    all

install -m 0755 diag-router "$OUT_DIR/diag-router"
install -m 0755 send_data "$OUT_DIR/send_data"

cd "$REPO_ROOT"
aarch64-linux-gnu-gcc -Wall -Wextra -O2 \
    tools/diag-capture.c \
    -o "$OUT_DIR/diag-capture"
chmod 0755 "$OUT_DIR/diag-capture"

file "$OUT_DIR/diag-router" "$OUT_DIR/send_data" "$OUT_DIR/diag-capture"
