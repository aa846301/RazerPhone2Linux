#!/bin/bash
# Hypothesis test: the TFA9912s are configured (factory container) for 64 BCK/frame, 32-bit slots, while mainline
# sdm845.c drives QUAT MI2S with 32 BCK/frame (S16, 1.536 MHz) -> CLKOOR=1, PLL never locks, no sound.
# While a tone plays, rewrite the TDM fields of both amps for 32 BCK/frame, 16-bit slots and watch status + mic.
# Register changes are volatile (the driver rewrites them on the next cold start); nothing is stored in MTP.
# Usage: tfa_tdm16_test.sh [hz] [dbfs]
set -u
HZ=${1:-1000}; DB=${2:--18}
CARD=0; W=/tmp/spk3; mkdir -p $W
PY=${PY:-$HOME/voice/venv/bin/python}
rd() { v=$(sudo i2cget -f -y 5 $1 $2 w 2>/dev/null); printf "0x%02x%02x" $((v & 0xff)) $((v >> 8)); }
wr() { sudo i2cset -f -y 5 $1 $2 $(( (($3 & 0xff) << 8) | ($3 >> 8) )) w; }   # TFA is big-endian on the wire
st() { for a in 0x34 0x35; do printf "%s: st0=%s st3=%s st4=%s  " $a "$(rd $a 0x10)" "$(rd $a 0x13)" "$(rd $a 0x14)"; done; echo; }

sudo /usr/local/sbin/razer-mic-setup mono 96 >/dev/null 2>&1
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
$PY - "$HZ" "$DB" "$W/tone.wav" <<'EOF'
import sys, wave, numpy as np
hz, db, out = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
sr = 48000; t = np.arange(int(sr * 6.0)) / sr
x = (10 ** (db / 20)) * np.sin(2 * np.pi * hz * t) * np.minimum(1, np.minimum(t, t[::-1]) / 0.05)
st = np.repeat((x * 32767).astype(np.int16)[:, None], 2, axis=1)
with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes(st.tobytes())
EOF

sudo arecord -q -D hw:$CARD,1 -f S16_LE -r 48000 -c 1 -d 10 $W/rec.wav &
REC=$!
sleep 2.0
sudo aplay -q -D plughw:$CARD,0 $W/tone.wav &      # tone from t=2 s to t=8 s
PLAY=$!
sleep 1.5
echo "before (t=3.5s): $(st)"
for a in 0x34 0x35; do
  r20=$(rd $a 0x20); r21=$(rd $a 0x21); r22=$(rd $a 0x22)
  n20=$(( r20 & 0x0fff ))                              # TDMNBCK = 0 -> 32 BCK per frame
  n21=$(( (r21 & ~(0x1f << 4)) | (15 << 4) ))          # TDMSLLN = 15 -> 16 bits per slot
  n22=$(( (r22 & ~(0x1f << 2)) | (15 << 2) ))          # TDMSSIZE = 15 -> 16-bit samples
  printf "amp %s: 0x20 %s->0x%04x  0x21 %s->0x%04x  0x22 %s->0x%04x\n" $a $r20 $n20 $r21 $n21 $r22 $n22
  wr $a 0x20 $n20; wr $a 0x21 $n21; wr $a 0x22 $n22
done                                                   # done at about t=4 s
sleep 0.3; echo "after TDM retune: $(st)"
if [ "${SET_MANSCONF:-1}" = 1 ]; then
  # Device manager sits in MANWAIT1 ("wait HW I2C settings") until MANSCONF (reg 0x01 bit 2) is set.
  for a in 0x34 0x35; do r1=$(rd $a 0x01); wr $a 0x01 $(( r1 | 0x0004 )); printf "amp %s: 0x01 %s->0x%04x\n" $a $r1 $(( r1 | 0x0004 )); done
fi
for i in 1 2 3 4; do sleep 0.4; echo "after +$((i*4))00ms: $(st)"; done
wait $PLAY; wait $REC; sudo chown "$(id -u)" $W/rec.wav

$PY - "$HZ" "$W/rec.wav" <<'EOF'
import sys, wave, numpy as np
hz, path = float(sys.argv[1]), sys.argv[2]
with wave.open(path) as w:
    sr = w.getframerate(); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768
def band(a, b):
    seg = x[int(a * sr):int(b * sr)]
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2; f = np.fft.rfftfreq(len(seg), 1 / sr)
    return 10 * np.log10(sp[(f > hz - 15) & (f < hz + 15)].sum() / len(seg) + 1e-20)
quiet, old, new, tail = band(0.8, 1.8), band(2.4, 3.4), band(5.5, 7.5), band(8.6, 9.6)
print(f"{hz:.0f} Hz band: silence {quiet:.1f} dB | tone, factory TDM (64 BCK) {old:.1f} dB | "
      f"tone, 16-bit TDM {new:.1f} dB | after {tail:.1f} dB")
rise = new - max(quiet, old, tail)
print(f"RESULT: {rise:+.1f} dB -> {'SPEAKER AUDIBLE' if rise > 15 else ('weak/uncertain' if rise > 6 else 'no sound')}")
EOF
