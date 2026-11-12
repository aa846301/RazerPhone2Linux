#!/bin/bash
# Steady-state speaker->mic latency: keep the output running (silence), then play the noise burst and find it in the
# raw DMIC recording by cross-correlation. pw-play start-up (~tens of ms) is included; device wake-up is not.
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
python3 -c "
import wave, numpy as np
st = np.zeros((48000 * 40, 2), np.int16)
w = wave.open('/tmp/silence40.wav', 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000); w.writeframes(st.tobytes()); w.close()"
pw-play /tmp/silence40.wav & S=$!
sleep 4
PIPEWIRE_NODE=razer_dmic arecord -q -D pipewire -f S16_LE -r 48000 -c 1 -d 8 /tmp/lat_mic.wav &
R=$!
sleep 1
T0=$(date +%s.%N)
pw-play /tmp/aec_noise.wav & P=$!
wait $R
kill $P $S 2>/dev/null
python3 - <<'EOF'
import wave, numpy as np
def rd(p):
    w = wave.open(p); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float) / 32768
    return x.reshape(-1, w.getnchannels())[:, 0]
ref, mic = rd("/tmp/aec_noise.wav")[:48000 * 3], rd("/tmp/lat_mic.wav")
n = 1 << 20
c = np.fft.irfft(np.fft.rfft(mic, n) * np.conj(np.fft.rfft(ref, n)), n)[:48000 * 7]
lag = int(np.argmax(np.abs(c))) / 48
print(f"noise appears in the mic recording at {lag:.0f} ms; pw-play was started ~1000 ms after the recording")
print(f"=> speaker->mic latency (incl. pw-play start) ~ {lag - 1000:.0f} ms")
EOF
