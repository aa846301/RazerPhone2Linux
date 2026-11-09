#!/bin/bash
# Route the Razer Phone 2 digital microphones to ALSA capture (hw:0,1,
# MultiMedia2 <- SLIMBUS_0_TX <- WCD9340 AIF1_CAP).
#
# Source of truth: stock /vendor/etc/mixer_paths_tavil.xml (aura P-3201):
#   handset-mic / speaker-mic / voice-rec-mic -> DMIC1 (primary)
#   *-dmic-endfire                            -> DMIC1 + DMIC3 (two channels)
#   DEC gain 96 = +12 dB on the voice decimators.
# Mainline names the decimator/TX slots differently from the stock TX7/TX8
# choice; DEC0/DEC1 on SLIM TX0/TX1 are used here and verified on device.
#
# Usage: razer-mic-setup [mono|stereo] [DEC_GAIN(0..124, 84=0dB)]
set -euo pipefail

MODE=${1:-mono}
GAIN=${2:-96}
CARD=${RAZER_MIC_CARD:-0}

cset() { amixer -q -c "$CARD" cset name="$1" "$2"; }

cset 'MultiMedia2 Mixer SLIMBUS_0_TX' 1
cset 'AIF1_CAP Mixer SLIM TX0' 1
cset 'CDC_IF TX0 MUX' DEC0
cset 'ADC MUX0' DMIC
cset 'DMIC MUX0' DMIC1
cset 'DEC0 Volume' "$GAIN"
cset 'TX0 HPF cut off' CF_NEG_3DB_150HZ

if [ "$MODE" = stereo ]; then
    cset 'AIF1_CAP Mixer SLIM TX1' 1
    cset 'CDC_IF TX1 MUX' DEC1
    cset 'ADC MUX1' DMIC
    cset 'DMIC MUX1' DMIC3
    cset 'DEC1 Volume' "$GAIN"
    cset 'TX1 HPF cut off' CF_NEG_3DB_150HZ
else
    cset 'AIF1_CAP Mixer SLIM TX1' 0
fi
