#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$REPO_ROOT/.tmp"
PDM_DIR="$TMP_DIR/pd-mapper"
QRTR_DIR="$TMP_DIR/qrtr"
OUT_DIR="$REPO_ROOT/output/pd-mapper-live"

if [ -e "$OUT_DIR" ] && [ ! -d "$OUT_DIR" ]; then
    rm -f "$OUT_DIR"
fi
mkdir -p "$TMP_DIR" "$OUT_DIR"

if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "missing aarch64-linux-gnu-gcc"
    exit 2
fi

if [ ! -d "$QRTR_DIR/.git" ]; then
    git clone --depth=1 https://github.com/linux-msm/qrtr.git "$QRTR_DIR"
fi

if [ ! -d "$PDM_DIR/.git" ]; then
    git clone --depth=1 https://github.com/linux-msm/pd-mapper.git "$PDM_DIR"
fi

BUILD_DIR="$TMP_DIR/pd-mapper-live-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/include"
cp "$PDM_DIR/pd-mapper.c" "$BUILD_DIR/pd-mapper-live.c"

# The live diagnostic only needs uncompressed modemr.jsn/modemuw.jsn. Avoid a
# cross liblzma dependency so this can be built without changing WSL packages.
cat > "$BUILD_DIR/include/lzma.h" <<'EOF'
/* no-xz live diagnostic build */
EOF

cat > "$BUILD_DIR/lzma_stub.c" <<'EOF'
int lzma_decomp(const char *file)
{
	(void)file;
	return -1;
}
EOF

python3 - "$BUILD_DIR/pd-mapper-live.c" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    '\treq.name[sizeof(req.name)-1] = \'\\0\';\n',
    '\treq.name[sizeof(req.name)-1] = \'\\0\';\n'
    '\tfprintf(stderr, "[PD-MAPPER] get_domain_list from %u:%u service=%s\\n", pkt->node, pkt->port, req.name);\n'
)
text = text.replace(
    '\tif (resp.domain_list_len)\n'
    '\t\tresp.domain_list_valid = 1;\n',
    '\tif (resp.domain_list_len)\n'
    '\t\tresp.domain_list_valid = 1;\n'
    '\tfprintf(stderr, "[PD-MAPPER] get_domain_list response service=%s domains=%u\\n", req.name, resp.domain_list_len);\n'
)
path.write_text(text)
PY

cd "$PDM_DIR"
aarch64-linux-gnu-gcc \
    -Wall -O2 -g \
    -I"$BUILD_DIR/include" \
    -I"$PDM_DIR" \
    -I"$QRTR_DIR/include" \
    -I/usr/aarch64-linux-gnu/include \
    -o "$OUT_DIR/pd-mapper-live" \
    "$BUILD_DIR/pd-mapper-live.c" assoc.c json.c servreg_loc.c \
    "$BUILD_DIR/lzma_stub.c" \
    "$QRTR_DIR/lib/qrtr.c" \
    "$QRTR_DIR/lib/qmi.c" \
    "$QRTR_DIR/lib/logging.c"

file "$OUT_DIR/pd-mapper-live"
