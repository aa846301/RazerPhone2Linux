#!/bin/bash
# Controlled echo-cancellation measurement: a fixed 200-4000 Hz noise burst (12 s, level LVL dBFS) is played through
# the default sink (razer_aec_sink = echo reference); raw DMIC and echo-cancelled source are recorded together.
# Echo removal = (raw rise over silence) - (cancelled rise over silence), measured over the last 6 s.
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
LVL=${1:--18}
python3 - "$LVL" <<'EOF'
import sys, wave, numpy as np
lvl = float(sys.argv[1]); sr = 48000
x = np.random.default_rng(1).standard_normal(sr * 12)
X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / sr); X[(f < 200) | (f > 4000)] = 0
y = np.fft.irfft(X, len(x)); y *= 10 ** (lvl / 20) / y.std()
st = (np.repeat(np.clip(y, -1, 1)[:, None], 2, 1) * 32767).astype(np.int16)
with wave.open("/tmp/aec_noise.wav", "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes(st.tobytes())
EOF
rec() {  # node file seconds
    PIPEWIRE_NODE=$1 arecord -q -D pipewire -f S16_LE -r 48000 -c 1 -d $3 $2
}
rec razer_dmic /tmp/a0r.wav 5 & rec razer_aec_source /tmp/a0o.wav 5; wait
pw-play /tmp/aec_noise.wav & P=$!
sleep 0.5
rec razer_dmic /tmp/a1r.wav 11 & rec razer_aec_source /tmp/a1o.wav 11; wait
wait $P
python3 - <<'EOF'
import wave, numpy as np
def lvl(p, a, b):
    w = wave.open(p); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float) / 32768
    x = x[int(a * 48000):int(b * 48000)]
    X = np.fft.rfft(x * np.hanning(len(x))); f = np.fft.rfftfreq(len(x), 1 / 48000)
    band = (f > 300) & (f < 3500)
    return 10 * np.log10((np.abs(X[band]) ** 2).sum() + 1e-20)
r0, o0 = lvl("/tmp/a0r.wav", 1, 5), lvl("/tmp/a0o.wav", 1, 5)
# use the last 6 s (canceller converged); scale silence windows (4 s) to the same length (+1.76 dB)
r1, o1 = lvl("/tmp/a1r.wav", 4.5, 10.5), lvl("/tmp/a1o.wav", 4.5, 10.5)
r0 += 1.76; o0 += 1.76
print(f"300-3500 Hz energy | silence raw {r0:.1f} cancelled {o0:.1f} | playing raw {r1:.1f} cancelled {o1:.1f}")
print(f"rise over silence: raw {r1 - r0:+.1f} dB, cancelled {o1 - o0:+.1f} dB -> echo removed {(r1 - r0) - (o1 - o0):.1f} dB")
EOF
