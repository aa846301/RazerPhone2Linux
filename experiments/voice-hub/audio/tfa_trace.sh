#!/bin/bash
# Play the 1 kHz tone and print the TFA9912 register traffic the driver logged during start/stop (left amp 0x34),
# plus a decode of status register 0x10 values seen and direct reads of key registers mid-playback.
CARD=0
[ -f /tmp/spk2/tone1000.wav ] || { echo "run speaker_loopback2.sh first"; exit 1; }
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
rd() { v=$(sudo i2cget -f -y 5 $1 $2 w 2>/dev/null); printf "0x%02x%02x" $((v & 0xff)) $((v >> 8)); }
mark=$(sudo dmesg | wc -l)
sudo aplay -q -D plughw:$CARD,0 /tmp/spk2/tone1000.wav &
p=$!
sleep 1.5
echo "== direct reads mid-playback (big-endian corrected)"
for a in 0x34 0x35; do
  echo "amp $a: SYS_CTRL0[00]=$(rd $a 0x00) SYS_CTRL1[01]=$(rd $a 0x01) SYS_CTRL2[02]=$(rd $a 0x02) STATUS0[10]=$(rd $a 0x10) STATUS1[11]=$(rd $a 0x11) STATUS3[13]=$(rd $a 0x13) STATUS4[14]=$(rd $a 0x14) TDM[20]=$(rd $a 0x20) TDM[21]=$(rd $a 0x21) MTP[f0]=$(rd $a 0xf0)"
done
wait $p
echo "== driver traffic for 5-0034 during this playback"
sudo dmesg | tail -n +$((mark + 1)) | grep "tfa98xx 5-0034" | sed -E 's/^\[ *([0-9.]+)\] tfa98xx 5-0034: /\1 /' | cut -c1-110
