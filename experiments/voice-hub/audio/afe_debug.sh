#!/bin/bash
# Enable dynamic debug for the Q6 AFE / sdm845 machine path, play the tone once, dump what the ADSP was asked to do
# (port start, clock set) and any errors; dynamic debug is switched back off on exit.
CARD=0
DD=/sys/kernel/debug/dynamic_debug/control
FILES="q6afe.c q6afe-dai.c q6afe-clocks.c sdm845.c q6asm-dai.c q6routing.c qdsp6/audioreach.c"
on()  { for f in $FILES; do echo "file $f +p" | sudo tee $DD >/dev/null 2>&1; done; }
off() { for f in $FILES; do echo "file $f -p" | sudo tee $DD >/dev/null 2>&1; done; }
trap off EXIT
sudo grep -cE "q6afe|sdm845.c" $DD
on
mark=$(sudo dmesg | wc -l)
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
sudo aplay -q -D plughw:$CARD,0 /tmp/spk2/tone1000.wav
sudo dmesg | tail -n +$((mark + 1)) | grep -vE "tfa98xx .*(RD|WR)\s" | cut -c1-220 | tail -60
