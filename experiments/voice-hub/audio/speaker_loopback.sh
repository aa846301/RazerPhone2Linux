#!/bin/bash
# Speaker loopback: play a 1 kHz tone on the speaker path (MultiMedia1 -> QUAT_MI2S_RX -> 2x TFA9912) while
# recording the DMIC (MultiMedia2, hw:0,1), then measure the 1 kHz energy during vs before playback.
# Also snapshots PCM state, TFA9912 status-related kernel messages and the QUAT MI2S pin state during playback.
# Usage: speaker_loopback.sh [tone_hz] [amplitude_dbfs]
set -u
HZ=${1:-1000}
DB=${2:--12}
W=/tmp/spk
mkdir -p $W
PY=${PY:-$HOME/voice/venv/bin/python}
CARD=0

sudo /usr/local/bin/razer-mic-setup mono 96 >/dev/null 2>&1 || sudo bash ~/voice/razer-mic-setup.sh mono 96
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1

$PY - "$HZ" "$DB" "$W/tone.wav" <<'EOF'
import sys, wave, numpy as np
hz, db, out = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
sr = 48000
t = np.arange(int(sr * 3.0)) / sr
x = (10 ** (db / 20)) * np.sin(2 * np.pi * hz * t)
fade = np.minimum(1, np.minimum(t, t[::-1]) / 0.02)
s = (x * fade * 32767).astype(np.int16)
st = np.repeat(s[:, None], 2, axis=1)
with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes(st.tobytes())
EOF

mark=$(sudo dmesg | wc -l)
sudo arecord -q -D hw:$CARD,1 -f S16_LE -r 48000 -c 1 -d 5 $W/rec.wav &
REC=$!
sleep 0.8
sudo aplay -q -D plughw:$CARD,0 $W/tone.wav &
PLAY=$!
sleep 1.2
echo "== during playback"
cat /proc/asound/card$CARD/pcm0p/sub0/status 2>/dev/null | head -4
cat /proc/asound/card$CARD/pcm1c/sub0/status 2>/dev/null | head -2
sudo cat /sys/kernel/debug/pinctrl/*tlmm*/pinconf-groups 2>/dev/null | grep -E "gpio5[89]|gpio6[0-1]" | head -4
sudo grep -E "gpio5[89]|gpio6[0-1]" /sys/kernel/debug/gpio 2>/dev/null | head -4
wait $PLAY; wait $REC; sudo chown $(id -u) $W/rec.wav
echo "== kernel messages during test"
sudo dmesg | tail -n +$((mark + 1)) | grep -iE "tfa|quat|mi2s|q6|asm|afe|clk|pll|error|fail" | grep -vE "RD\s+reg|WR reg" | tail -15 | cut -c1-200
echo "== TFA register traffic during test: $(sudo dmesg | tail -n +$((mark + 1)) | grep -cE 'tfa98xx.*(RD|WR)')"

$PY - "$HZ" "$W/rec.wav" <<'EOF'
import sys, wave, numpy as np
hz, path = float(sys.argv[1]), sys.argv[2]
with wave.open(path) as w:
    sr = w.getframerate(); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768
def band(seg):
    if len(seg) < 4096: return float("nan"), float("nan")
    win = np.hanning(len(seg)); sp = np.abs(np.fft.rfft(seg * win)) ** 2
    f = np.fft.rfftfreq(len(seg), 1 / sr)
    tone = sp[(f > hz - 15) & (f < hz + 15)].sum()
    noise = np.median(sp[(f > 300) & (f < 6000)]) * ((f > hz - 15) & (f < hz + 15)).sum()
    return 10 * np.log10(tone + 1e-20), 10 * np.log10(noise + 1e-20)
pre = x[int(0.1 * sr):int(0.7 * sr)]
dur = x[int(1.3 * sr):int(3.3 * sr)]
post = x[int(4.2 * sr):int(4.9 * sr)]
tp, npre = band(pre); td, nd = band(dur); tq, _ = band(post)
rms = lambda s: 20 * np.log10(np.sqrt(np.mean(s ** 2)) + 1e-12)
print(f"recorded {len(x)/sr:.1f}s  rms pre {rms(pre):.1f} dBFS, during {rms(dur):.1f} dBFS, after {rms(post):.1f} dBFS")
print(f"{hz:.0f} Hz band: pre {tp:.1f} dB, during {td:.1f} dB, after {tq:.1f} dB (noise floor ~{nd:.1f} dB)")
rise = td - max(tp, tq)
print(f"RESULT: tone rise {rise:+.1f} dB -> {'SPEAKER AUDIBLE' if rise > 15 else ('weak/uncertain' if rise > 6 else 'NO SOUND DETECTED')}")
EOF
