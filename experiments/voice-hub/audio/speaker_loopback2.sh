#!/bin/bash
# Speaker loopback v2: controlled A/B. For each tone, record 7 s from the DMIC; play the tone (3 s) starting at 2.0 s
# (skipping the mic start-up transient), or play nothing (control). Compare tone-band energy in the play window
# against the same window of the control recording. Reads the TFA9912 status register (0x10) while playing.
# Usage: speaker_loopback2.sh [amplitude_dbfs] [tones...]
set -u
DB=${1:--12}; shift || true
TONES=${*:-1000 2500}
W=/tmp/spk2; mkdir -p $W
PY=${PY:-$HOME/voice/venv/bin/python}
CARD=0
sudo /usr/local/sbin/razer-mic-setup mono 96 >/dev/null 2>&1
sudo amixer -q -c $CARD cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1

mktone() {  # hz file
  $PY - "$1" "$DB" "$2" <<'EOF'
import sys, wave, numpy as np
hz, db, out = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
sr = 48000; t = np.arange(int(sr * 3.0)) / sr
x = (10 ** (db / 20)) * np.sin(2 * np.pi * hz * t) * np.minimum(1, np.minimum(t, t[::-1]) / 0.02)
st = np.repeat((x * 32767).astype(np.int16)[:, None], 2, axis=1)
with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes(st.tobytes())
EOF
}

tfa_status() {  # read status word 0x10 of both amps (driver owns the bus: -f, read-only)
  for a in 0x34 0x35; do printf "%s:%s " $a "$(sudo i2cget -f -y 5 $a 0x10 w 2>/dev/null)"; done
}

run() {  # label hz play(0/1)
  rm -f $W/$1.wav
  sudo arecord -q -D hw:$CARD,1 -f S16_LE -r 48000 -c 1 -d 7 $W/$1.wav &
  local rec=$!
  sleep 2.0
  if [ "$3" = 1 ]; then
    sudo aplay -q -D plughw:$CARD,0 $W/tone$2.wav &
    local p=$!; sleep 1.0
    echo "   $1: TFA status during playback: $(tfa_status)"
    wait $p || { echo "ERROR: aplay failed"; exit 2; }
  fi
  wait $rec || { echo "ERROR: arecord failed"; exit 2; }
  [ -s $W/$1.wav ] || { echo "ERROR: no recording"; exit 2; }
  sudo chown "$(id -u)" $W/$1.wav
}

echo "TFA status idle: $(tfa_status)"
for hz in $TONES; do
  mktone $hz $W/tone$hz.wav
  run ctl$hz $hz 0
  run spk$hz $hz 1
done

$PY - $W $TONES <<'EOF'
import sys, wave, numpy as np
W, tones = sys.argv[1], [float(t) for t in sys.argv[2:]]
def load(p):
    with wave.open(p) as w:
        return w.getframerate(), np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32768
def band_db(x, sr, hz, a, b):
    seg = x[int(a * sr):int(b * sr)]
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2; f = np.fft.rfftfreq(len(seg), 1 / sr)
    return 10 * np.log10(sp[(f > hz - 15) & (f < hz + 15)].sum() + 1e-20)
for hz in tones:
    sr, c = load(f"{W}/ctl{int(hz)}.wav"); _, s = load(f"{W}/spk{int(hz)}.wav")
    win = (2.4, 4.6)
    d_ctl, d_spk = band_db(c, sr, hz, *win), band_db(s, sr, hz, *win)
    d_pre = band_db(s, sr, hz, 0.8, 1.9)
    rise = d_spk - max(d_ctl, d_pre)
    verdict = "SPEAKER AUDIBLE" if rise > 15 else ("weak/uncertain" if rise > 6 else "NO SOUND")
    print(f"{hz:6.0f} Hz: play-window {d_spk:6.1f} dB | control same window {d_ctl:6.1f} dB | "
          f"pre-play {d_pre:6.1f} dB -> rise {rise:+5.1f} dB  {verdict}")
EOF
