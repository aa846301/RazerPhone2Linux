#!/bin/bash
# Build the HexagonFS tree hexagonrpcd serves to the SLPI (sensor DSP) from the factory images, so the Qualcomm
# Sensor Core (ambient light / proximity STK3x1x, BMI160, BMM150) works on mainline. Files are proprietary:
# keep them out of git; install the tarball on the phone.
#
# Usage (WSL/Linux, needs debugfs from e2fsprogs and sscregistrygen from linux-msm/hexagonrpc):
#   extract-sensor-firmware.sh <factory dir with dsp.raw + vendor.raw> <out.tgz> [sscregistrygen]
# Phone: sudo mkdir -p /usr/share/qcom/sdm845/Razer/aura && sudo tar -xzf out.tgz -C /usr/share/qcom/sdm845/Razer/aura
#
# dsp.raw / vendor.raw are the raw ext4 images from the factory zip (tools/simg2raw.py on the sparse images).
set -euo pipefail
F=$(readlink -f "$1")
OUT=$(readlink -f "$2")
GEN=${3:-sscregistrygen}
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT

mkdir -p "$S/dsp" "$S/sensors/registry" "$S/socinfo"
debugfs -R "rdump /sdsp $S/dsp" "$F/dsp.raw"                                   # SLPI userspace libraries
debugfs -R "rdump /etc/sensors/config $S/sensors" "$F/vendor.raw"             # per-sensor JSON configs
debugfs -R "dump /etc/sensors/sns_reg_config $S/sensors/sns_reg.conf" "$F/vendor.raw"

# Mainline socinfo has no hw_platform/platform_subtype; the configs for this board (STK3x1x, BMI160, BMM150)
# match soc_id 321 (SDM845) with hw_platform MTP, so present those to the DSP.
printf 'MTP\n' >"$S/socinfo/hw_platform"
printf '321\n' >"$S/socinfo/soc_id"
printf '2.1\n' >"$S/socinfo/revision"
printf 'Unknown\n' >"$S/socinfo/platform_subtype"
printf '0\n' >"$S/socinfo/platform_subtype_id"
printf '0\n' >"$S/socinfo/platform_version"

# hexagonrpcd refuses writes, so the registry the SLPI would otherwise build on first boot is pre-generated.
"$GEN" -p MTP -s 321 "$S/sensors/config" "$S/sensors/registry"

echo "sdsp libs: $(ls "$S/dsp/sdsp" | wc -l), configs: $(ls "$S/sensors/config" | wc -l), registry: $(ls "$S/sensors/registry" | wc -l)"
ls "$S/sensors/registry" | grep -q '^stk3x1x_0.ambient_light$' || { echo "ERROR: no stk3x1x light sensor in registry"; exit 1; }
tar -czf "$OUT" -C "$S" .
echo "wrote $OUT"
