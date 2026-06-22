#!/bin/bash
set -euo pipefail

KDIR=~/razorphone2linux/kernel/linux
PROJ=/mnt/c/repo/razorphone2linux

echo "=== Copying files ==="
cp "$PROJ/dts/sdm845-razer-aura.dts" "$KDIR/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts"
dos2unix "$KDIR/arch/arm64/boot/dts/qcom/sdm845-razer-aura.dts"

cp "$PROJ/panel-driver/panel-novatek-nt36830.c" "$KDIR/drivers/gpu/drm/panel/panel-novatek-nt36830.c"
dos2unix "$KDIR/drivers/gpu/drm/panel/panel-novatek-nt36830.c"

echo "Files copied and line endings fixed"

echo "=== Patching DTS Makefile ==="
DTS_MK="$KDIR/arch/arm64/boot/dts/qcom/Makefile"
if ! grep -q "sdm845-razer-aura" "$DTS_MK"; then
    LAST=$(grep -n "sdm845-" "$DTS_MK" | tail -1 | cut -d: -f1)
    if [ -n "$LAST" ]; then
        sed -i "${LAST}a\\dtb-\$(CONFIG_ARCH_QCOM) += sdm845-razer-aura.dtb" "$DTS_MK"
        echo "DTS Makefile patched after line $LAST"
    else
        echo "dtb-\$(CONFIG_ARCH_QCOM) += sdm845-razer-aura.dtb" >> "$DTS_MK"
        echo "DTS Makefile patched (appended)"
    fi
else
    echo "DTS Makefile already patched"
fi

echo "=== Patching Panel Kconfig ==="
PANEL_KC="$KDIR/drivers/gpu/drm/panel/Kconfig"
if ! grep -q "DRM_PANEL_NOVATEK_NT36830" "$PANEL_KC"; then
    cat >> "$PANEL_KC" << 'KCEOF'

config DRM_PANEL_NOVATEK_NT36830
	tristate "NovaTeK NT36830 Dual-DSI AMOLED panel with DSC"
	depends on OF
	depends on DRM_MIPI_DSI
	depends on BACKLIGHT_CLASS_DEVICE
	help
	  Say Y or M here if you want to enable support for the NovaTeK
	  NT36830 AMOLED display panel used in the Razer Phone 2.
	  This panel uses Dual DSI with Display Stream Compression (DSC)
	  at 1440x2560 resolution.
KCEOF
    echo "Panel Kconfig patched"
else
    echo "Panel Kconfig already patched"
fi

echo "=== Patching Panel Makefile ==="
PANEL_MK="$KDIR/drivers/gpu/drm/panel/Makefile"
if ! grep -q "panel-novatek-nt36830" "$PANEL_MK"; then
    echo 'obj-$(CONFIG_DRM_PANEL_NOVATEK_NT36830) += panel-novatek-nt36830.o' >> "$PANEL_MK"
    echo "Panel Makefile patched"
else
    echo "Panel Makefile already patched"
fi

echo "===PATCH_DONE==="
