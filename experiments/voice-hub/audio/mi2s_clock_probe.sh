#!/bin/bash
# Is the QUAT MI2S bit clock actually toggling? Sample the TLMM input level of GPIO58 (SCK), 59 (WS), 61 (SD1)
# many times via debugfs while a tone plays; a running clock reads as a mix of 0/1, a dead one as constant.
CARD=0
W=/tmp/spk2
[ -f $W/tone1000.wav ] || { echo "run speaker_loopback2.sh first (needs $W/tone1000.wav)"; exit 1; }
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
sample() {
  sudo sh -c 'for i in $(seq 1 300); do grep -E "gpio5[89] |gpio61 " /sys/kernel/debug/gpio; done' | \
    awk '{n[$1]++; if ($0 ~ / high/) h[$1]++} END {for (g in n) printf "%s high %d/%d  ", g, h[g], n[g]; print ""}'
}
echo "idle:    $(sample)"
sudo aplay -q -D plughw:$CARD,0 $W/tone1000.wav &
p=$!; sleep 0.8
echo "playing: $(sample)"
wait $p
echo "== clock-related kernel lines since boot"
sudo dmesg | grep -iE "mi2s|quat|lpass.*clk|afe.*clk|set_sysclk|bclk|ibit" | tail -10 | cut -c1-200
