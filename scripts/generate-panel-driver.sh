#!/bin/bash
# Generate an auditable NT36830 reference from the factory DTBO using lmdpdg.
# The generated files are reference material; they do not automatically replace
# the hand-reviewed dual-DSI/DSC production driver.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/config/panel-generator.env"

DTBO_IMG="${1:-$PROJECT_DIR/aura-p-release-3201-user-full/aura-p-release-3201/dtbo.img}"
WORK_DIR="$PROJECT_DIR/.tmp/panel-generator-work"
GENERATOR_DIR="$PROJECT_DIR/.tmp/panel-generator"
PYLIBFDT_DIR="$PROJECT_DIR/.tmp/pylibfdt"
RESULT_DIR="$PROJECT_DIR/panel-driver/generated-reference"

if [ ! -f "$DTBO_IMG" ]; then
    echo "ERROR: factory DTBO image not found: $DTBO_IMG"
    exit 1
fi

if [ ! -d "$GENERATOR_DIR/.git" ]; then
    git clone --filter=blob:none "$PANEL_GENERATOR_REPO" "$GENERATOR_DIR"
fi
git -C "$GENERATOR_DIR" fetch --depth=1 origin "$PANEL_GENERATOR_COMMIT"
git -C "$GENERATOR_DIR" checkout --detach "$PANEL_GENERATOR_COMMIT"

if ! PYTHONPATH="$PYLIBFDT_DIR${PYTHONPATH:+:$PYTHONPATH}" \
        python3 -c 'import libfdt' >/dev/null 2>&1; then
    echo "Installing pylibfdt into the repo-local .tmp cache..."
    python3 -m pip install --target "$PYLIBFDT_DIR" pylibfdt
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/dtbs" "$WORK_DIR/generated"
python3 "$PROJECT_DIR/tools/extract-android-dtbo.py" \
    "$DTBO_IMG" "$WORK_DIR/dtbs"

for dtb in "$WORK_DIR"/dtbs/*.dtb; do
    dtc -I dtb -O dts -o "${dtb%.dtb}.dts" "$dtb" 2>/dev/null || true
done

(
    cd "$WORK_DIR/generated"
    PYTHONPATH="$PYLIBFDT_DIR${PYTHONPATH:+:$PYTHONPATH}" \
        python3 "$GENERATOR_DIR/lmdpdg.py" "$WORK_DIR"/dtbs/*.dtb
)

rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"
find "$WORK_DIR/generated" -mindepth 1 -maxdepth 1 -type d \
    -iname '*nt36830*' -exec cp -a {} "$RESULT_DIR/" \;

echo "Generated reference files:"
find "$RESULT_DIR" -type f -printf '  %P\n' | sort
echo "Review these against panel-driver/panel-novatek-nt36830.c."
