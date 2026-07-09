#!/bin/bash
# ==========================================================================
# Razer Phone 2 (aura) - CI entrypoint (GitHub Actions / any Ubuntu 24.04)
# ==========================================================================
# One command that reproduces the full flashable image set from a clean
# checkout, using the exact same pipeline as local development:
#   01-setup-environment.sh -> 02-build-kernel.sh (native panel + GPU)
#   -> 03-build-rootfs.sh (debootstrap, needs root) -> 04-make-boot-image.sh
#
# The build consumes repository source/config plus firmware imported into the
# temporary checkout from RAZER_FACTORY_ZIP_URL when that secret is configured.
#
# Usage: bash scripts/ci-build.sh
#   (sudo is used internally where required; the caller needs passwordless
#    sudo, which GitHub-hosted runners provide)
#
# Outputs land in <repo>/output/base/:
#   boot.img, rootfs-sparse.img, rootfs.img, Image.gz-dtb, kernel.config,
#   kernel.release, initrd.img-*, vbmeta_disabled.img, SHA256SUMS
# ==========================================================================
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"

# 01-setup-environment.sh hardcodes the workspace to $HOME/razorphone2linux;
# every later stage defaults to the same path, so do not set RAZER_WORKDIR.
export RAZER_IMAGE_PROFILE=base
if [ -z "${RAZER_USERSPACE_PROFILE:-}" ]; then
    case "${GITHUB_REF_NAME:-}" in
        *-ha) export RAZER_USERSPACE_PROFILE=ha ;;
        *-3dprinter) export RAZER_USERSPACE_PROFILE=3dprinter ;;
        *) export RAZER_USERSPACE_PROFILE=none ;;
    esac
fi
case "$RAZER_USERSPACE_PROFILE" in
    none|ha|3dprinter) ;;
    *) echo "ERROR: RAZER_USERSPACE_PROFILE must be none, ha, or 3dprinter."; exit 2 ;;
esac
# Production display mode: boot log stays visible until systemd is up, then
# razer-quiet-console silences the panel (see 04-make-boot-image.sh).
export RAZER_BOOT_DISPLAY_MODE=normal
# The validated display stack: native NT36830 panel + Adreno 630 (flips the
# DTS nodes and forces DRM_MSM/panel builtin in 02-build-kernel.sh).
export RAZER_DISPLAY_NATIVE_PANEL=1
# CI does not need the Android reference kernel checkout.
export RAZER_SKIP_REFERENCE=1

echo "CI userspace profile: $RAZER_USERSPACE_PROFILE"

echo "=== [ci 1/5] environment setup (apt deps + pinned kernel clone) ==="
# A cached/reused kernel checkout carries the integration commit that
# 02-build-kernel.sh creates, which would trip 01-setup's pinned-commit
# check. Reset to the pin first (same dance as the local _make-* scripts).
KLIN="$HOME/razorphone2linux/kernel/linux"
KC=$(. "$PROJ/config/kernel-source.env" && echo "$KERNEL_COMMIT")
if [ -d "$KLIN/.git" ]; then
    git -C "$KLIN" checkout --detach "$KC"
    git -C "$KLIN" branch -D razerphone2linux/integration 2>/dev/null || true
    git -C "$KLIN" reset --hard "$KC"
    git -C "$KLIN" clean -fd
fi
bash "$PROJ/scripts/01-setup-environment.sh"

echo "=== [ci 1b/5] firmware import ==="
if [ -n "${RAZER_FACTORY_ZIP_URL:-}" ]; then
    curl -L --fail --retry 3 \
        -o "$PROJ/aura-p-release-3201-user-full.zip" \
        "$RAZER_FACTORY_ZIP_URL"
    bash "$PROJ/scripts/extract-modem-firmware.sh"
elif [ -f "$PROJ/firmware/qcom/sdm845/Razer/aura/mba.mbn" ]; then
    echo "Using firmware already present in firmware/."
else
    cat >&2 <<'EOF'
ERROR: firmware/qcom/sdm845/Razer/aura/mba.mbn is missing.
Set the repository secret RAZER_FACTORY_ZIP_URL to a private URL for
aura-p-release-3201-user-full.zip, or pre-populate firmware/ on a self-hosted
runner. The native panel/GPU/WebKit artifact is not complete without the Razer
factory firmware payload.
EOF
    exit 1
fi

echo "=== [ci 2/5] kernel build ==="
bash "$PROJ/scripts/02-build-kernel.sh"

OUT="$HOME/razorphone2linux/output/base"

echo "=== [ci 3/5] architecture assertions ==="
# Panel/GPU are builtin for the native display path; the WiFi/modem chain
# must stay modular (staged bring-up order is load-bearing, see
# razer-wifi-ready.service). Fail loudly instead of shipping silent
# regressions.
for opt in DRM_MSM DRM_PANEL_NOVATEK_NT36830; do
    grep -q "^CONFIG_${opt}=y$" "$OUT/kernel.config" || {
        echo "ASSERT-FAIL: CONFIG_${opt} is not =y"; exit 1; }
done
for opt in QCOM_Q6V5_MSS ATH10K_SNOC; do
    grep -q "^CONFIG_${opt}=m$" "$OUT/kernel.config" || {
        echo "ASSERT-FAIL: CONFIG_${opt} is not =m (WiFi/modem regression)"; exit 1; }
done
KSIZE=$(stat -c%s "$OUT/Image.gz-dtb")
echo "kernel blob: ${KSIZE} bytes"
if [ "$KSIZE" -ge 32000000 ]; then
    echo "ASSERT-FAIL: kernel blob too large for ABL ramdisk_offset headroom"
    exit 1
fi

echo "=== [ci 4/5] rootfs build (debootstrap, as root) ==="
sudo -E bash "$PROJ/scripts/03-build-rootfs.sh"

echo "=== [ci 5/5] boot image ==="
bash "$PROJ/scripts/04-make-boot-image.sh"

echo "=== checksums ==="
cd "$PROJ/output/base"
printf '%s\n' "$RAZER_USERSPACE_PROFILE" > userspace.profile
sha256sum boot.img rootfs-sparse.img Image.gz-dtb kernel.config userspace.profile > SHA256SUMS
cat SHA256SUMS
echo "CI-BUILD-COMPLETE"
