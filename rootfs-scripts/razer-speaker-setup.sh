#!/bin/bash
# Make the two TFA9912 speaker amplifiers accept the I2S clock mainline actually sends.
#
# Razer's factory tfa98xx.cnt container configures the amps' TDM interface for 64 BCK per frame with 32-bit
# slots, because stock Android plays the speaker backend as S24_LE (QUAT_MI2S_RX Format in
# mixer_paths_tavil.xml -> 3.072 MHz bit clock). Mainline sound/soc/qcom/sdm845.c always drives QUAT MI2S as
# S16_LE with MI2S_BCLK_RATE = 1.536 MHz (32 BCK per frame). The amps then flag CLKOOR (reg 0x14 bit 2,
# "external clock out of range"), the PLL never locks, the device manager stays in MANWAIT1, and the phone is
# silent although the PCM runs and tfa_dev_start reports success.
#
# This rewrites three TDM fields on both amps for 32 BCK / 16-bit slots / 16-bit samples:
#   reg 0x20 TDMNBCK  [15:12] = 0   (32 BCK per frame)
#   reg 0x21 TDMSLLN  [8:4]   = 15  (16 bits per slot)
#   reg 0x22 TDMSSIZE [6:2]   = 15  (16-bit samples)
# The writes are volatile (not MTP) and idempotent. The driver loads the container once at probe and later
# starts are warm, so running this once after boot is enough; it is also safe to run before every playback.
# Verified by DMIC loopback on 2026-11-10: 1 kHz +66 dB, 2.5 kHz +84 dB over the no-playback control.
#
# Remove this once the machine driver drives the backend as 24-bit / 3.072 MHz like the factory.
# Usage: razer-speaker-setup [--check]   (exit 0 = amps configured for 16-bit, 1 = not/failed)
set -u
BUS=${RAZER_TFA_I2C_BUS:-5}
AMPS=${RAZER_TFA_ADDRS:-"0x34 0x35"}
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# Kernels carrying kernel-patches/0016 + 0017 already drive the backend as 24-bit / 3.072 MHz with standard I2S
# alignment; forcing the amps to 16-bit there would make them flag CLKOOR again. Detect that driver and step aside.
if grep -q ' sdm845_fe_startup\b' /proc/kallsyms 2>/dev/null; then
    echo "razer-speaker-setup: 24-bit QUAT MI2S driver present (patch 0016), nothing to do"
    exit 0
fi

command -v i2cget >/dev/null || { echo "razer-speaker-setup: i2c-tools missing" >&2; exit 1; }

# TFA registers are big-endian on the wire; SMBus word transfers are little-endian.
rd() { local v; v=$(i2cget -f -y "$BUS" "$1" "$2" w) || return 1; echo $(( ((v & 0xff) << 8) | (v >> 8) )); }
wr() { i2cset -f -y "$BUS" "$1" "$2" $(( (($3 & 0xff) << 8) | ($3 >> 8) )) w; }

rc=0
for a in $AMPS; do
    r20=$(rd "$a" 0x20) && r21=$(rd "$a" 0x21) && r22=$(rd "$a" 0x22) || {
        echo "razer-speaker-setup: amp $a not readable on i2c-$BUS" >&2; rc=1; continue; }
    n20=$(( r20 & 0x0fff ))
    n21=$(( (r21 & ~(0x1f << 4)) | (15 << 4) ))
    n22=$(( (r22 & ~(0x1f << 2)) | (15 << 2) ))
    if [ "$r20" = "$n20" ] && [ "$r21" = "$n21" ] && [ "$r22" = "$n22" ]; then
        continue
    fi
    if [ "$CHECK" = 1 ]; then
        rc=1
        continue
    fi
    wr "$a" 0x20 "$n20" && wr "$a" 0x21 "$n21" && wr "$a" 0x22 "$n22" || { rc=1; continue; }
    printf 'razer-speaker-setup: amp %s TDM 0x20 %04x->%04x 0x21 %04x->%04x 0x22 %04x->%04x\n' \
        "$a" "$r20" "$n20" "$r21" "$n21" "$r22" "$n22"
done
exit $rc
