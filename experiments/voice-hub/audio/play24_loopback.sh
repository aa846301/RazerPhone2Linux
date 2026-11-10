#!/bin/bash
# Loopback with a native-format FE stream on hw:0,0 (no plug conversion), to check whether the ASM (FE) / ADM (BE)
# bit-width mismatch matters. Usage: play24_loopback.sh <S16_LE|S24_LE> [hz]
set -u
FMT=$1; HZ=${2:-1000}; W=/tmp/spk3; mkdir -p $W; rm -f $W/*.wav $W/*.raw
PY=$HOME/voice/venv/bin/python
sudo /usr/local/sbin/razer-mic-setup mono 96 >/dev/null 2>&1
sudo amixer -q -c 0 cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 1
$PY - $FMT $HZ $W/tone.raw <<'EOF'
import sys, numpy as np
fmt, hz, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
sr = 48000; t = np.arange(sr * 3) / sr
import os; x = float(os.environ.get("AMP", "0.25")) * np.sin(2 * np.pi * hz * t) * np.minimum(1, np.minimum(t, t[::-1]) / 0.02)
if fmt == "S16_LE": d = (x * 32767).astype("<i2")
else:               d = (x * 8388607).astype("<i4")          # S24_LE: 24-bit value in a 32-bit container
np.repeat(d[:, None], 2, axis=1).tofile(out)
EOF
for run in ctl spk; do
  sudo arecord -q -D hw:0,1 -f S16_LE -r 48000 -c 1 -d 7 $W/$run.wav & rec=$!
  sleep 2
  if [ $run = spk ]; then
    sudo aplay -q -D hw:0,0 -t raw -f $FMT -r 48000 -c 2 $W/tone.raw || echo "ERROR: aplay $FMT failed"
  fi
  wait $rec
done
$PY - $W $HZ <<'EOF'
import sys, wave, numpy as np
W, hz = sys.argv[1], float(sys.argv[2])
def bd(p, a, b):
    x = np.frombuffer(wave.open(p).readframes(10**7), np.int16).astype(float) / 32768
    s = x[int(a*48000):int(b*48000)]; sp = np.abs(np.fft.rfft(s*np.hanning(len(s))))**2; f = np.fft.rfftfreq(len(s), 1/48000)
    return 10*np.log10(sp[(f > hz-15) & (f < hz+15)].sum() + 1e-20)
c, s = bd(f"{W}/ctl.wav", 2.4, 4.6), bd(f"{W}/spk.wav", 2.4, 4.6)
print(f"{hz:.0f} Hz: play {s:.1f} dB, control {c:.1f} dB, rise {s-c:+.1f} dB")
x = np.frombuffer(wave.open(f"{W}/spk.wav").readframes(10**7), np.int16).astype(float) / 32768
seg = x[int(2.4*48000):int(4.6*48000)]; sp = np.abs(np.fft.rfft(seg*np.hanning(len(seg))))**2; f = np.fft.rfftfreq(len(seg), 1/48000)
band = lambda h: sp[(f > h-15) & (f < h+15)].sum()
fund = band(hz); harm = sum(band(k*hz) for k in range(2, 8))
rest = sp[(f > 200) & (f < 16000)].sum() - fund
print(f"   harmonics 2-7: {10*np.log10(harm/fund):.1f} dBc, everything else 200-16k: {10*np.log10(rest/fund):.1f} dBc")
EOF
