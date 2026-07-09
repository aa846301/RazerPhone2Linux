#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$REPO_ROOT/.tmp"
SRC_DIR="$TMP_DIR/rmtfs-detail-src"
OUT_DIR="$REPO_ROOT/output/rmtfs-detail-live"
PATCH="$REPO_ROOT/tools/rmtfs-razer-detail-logging.patch"
RMTFS_REPO="https://github.com/linux-msm/rmtfs.git"
RMTFS_COMMIT="14cb1ee69f556873dc271832b77163669e1d6459"

mkdir -p "$TMP_DIR" "$OUT_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
	git clone "$RMTFS_REPO" "$SRC_DIR"
fi

cd "$SRC_DIR"
git fetch origin
git reset --hard "$RMTFS_COMMIT"
git clean -xfd
git apply "$PATCH"

tar --exclude=.git -czf "$OUT_DIR/rmtfs-detail-source.tar.gz" -C "$SRC_DIR" .
sha256sum "$OUT_DIR/rmtfs-detail-source.tar.gz" > "$OUT_DIR/rmtfs-detail-source.tar.gz.sha256.txt"

copied_debs=0
for deb in \
	"$TMP_DIR"/libqrtr-dev_*_arm64.deb \
	"$TMP_DIR"/libudev-dev_*_arm64.deb
do
	if [ -e "$deb" ]; then
		cp -f "$deb" "$OUT_DIR/"
		sha256sum "$OUT_DIR/$(basename "$deb")" > "$OUT_DIR/$(basename "$deb").sha256.txt"
		copied_debs=1
	fi
done

cat <<EOF
Prepared rmtfs-detail live source:
  $OUT_DIR/rmtfs-detail-source.tar.gz

Copy to phone with the two arm64 dev debs, then run:
  bash scripts/phone-build-rmtfs-detail-live.sh

The phone build script only writes under /tmp and produces /tmp/rmtfs-detail.
EOF

if [ "$copied_debs" -eq 0 ]; then
	cat <<EOF

Warning: no arm64 dev debs were found in $TMP_DIR.
Expected files:
  libqrtr-dev_*_arm64.deb
  libudev-dev_*_arm64.deb
EOF
fi
