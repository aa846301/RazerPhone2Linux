#!/bin/bash
# Trial-load a rebuilt snd-soc-sdm845.ko WITHOUT installing it, test the speaker by DMIC loopback, then always
# return the phone to its previous state (installed module + razer-speaker-setup 16-bit workaround).
# Usage: sndcard_trial.sh <new snd-soc-sdm845.ko>
set -u
NEW=$1
CARD=0
PY=${PY:-$HOME/voice/venv/bin/python}
rd() { v=$(sudo i2cget -f -y 5 $1 $2 w); printf "0x%02x%02x" $((v & 0xff)) $((v >> 8)); }
wr() { sudo i2cset -f -y 5 $1 $2 $(( (($3 & 0xff) << 8) | ($3 >> 8) )) w; }
status() { for a in 0x34 0x35; do printf "%s st0=%s st3=%s st4=%s tdm=%s/%s/%s  " $a "$(rd $a 0x10)" "$(rd $a 0x13)" \
  "$(rd $a 0x14)" "$(rd $a 0x20)" "$(rd $a 0x21)" "$(rd $a 0x22)"; done; echo; }

restore() {
  echo "== restore: installed module + 16-bit workaround"
  sudo rmmod snd_soc_sdm845 2>/dev/null
  sudo modprobe snd_soc_sdm845 && sleep 3
  sudo /usr/local/sbin/razer-speaker-setup
  echo "card: $(cat /proc/asound/cards | head -1)"
}
trap restore EXIT

[ -f "$NEW" ] || { echo "missing $NEW"; exit 1; }
echo "running: $(uname -r); new module vermagic: $(modinfo -F vermagic "$NEW")"
fuser -v /dev/snd/* 2>&1 | grep -v "^ *USER" | head -3

echo "== factory TDM (64 BCK, 32-bit slots, 24-bit samples) on both amps"
for a in 0x34 0x35; do wr $a 0x20 0x2890; wr $a 0x21 0xc1f1; wr $a 0x22 0x545c; done
status

mark=$(sudo dmesg | wc -l)
sudo rmmod snd_soc_sdm845 || { echo "rmmod failed"; exit 1; }
sudo insmod "$NEW" || { echo "insmod failed"; sudo dmesg | tail -5; exit 1; }
for i in $(seq 1 20); do grep -q "Razer Phone 2" /proc/asound/cards && break; sleep 0.5; done
echo "card after insmod: $(cat /proc/asound/cards | head -1)"
sudo dmesg | tail -n +$((mark + 1)) | grep -iE "sdm845|snd|asoc|quat|error|fail|tfa98xx.*(start|mute|err)" | head -15 | cut -c1-180

echo "== speaker loopback with the new module"
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
mark=$(sudo dmesg | wc -l)
timeout 120 bash ~/voice/audio/speaker_loopback2.sh -18 1000 2500
echo "== amp status right after"
sudo aplay -q -D plughw:$CARD,0 /tmp/spk2/tone1000.wav & p=$!; sleep 1.2; status; wait $p
sudo dmesg | tail -n +$((mark + 1)) | grep -iE "quat|error|fail|DSP returned|AFE" | head -10 | cut -c1-180
