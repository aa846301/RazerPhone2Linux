#!/bin/bash
# Echo-cancellation check: play a song on the hub player, record the raw DMIC and the echo-cancelled source at the
# same time, and compare their levels (music-only, nobody talking). Usage: aec_test.sh [query] [volume 0..1]
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
Q=${1:-晴天}; VOL=${2:-0.3}
set -a; . ~/.config/razer-voice/ha.env; set +a
P=media_player.razer_zhong_kong_tai
# Baseline: room noise with nothing playing, through both paths.
PIPEWIRE_NODE=razer_dmic arecord -q -D pipewire -f S16_LE -r 48000 -c 1 -d 6 /tmp/aec_raw0.wav &
PIPEWIRE_NODE=razer_aec_source arecord -q -D pipewire -f S16_LE -r 48000 -c 1 -d 6 /tmp/aec_out0.wav
wait
ha() { curl -s -m 30 -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" -d "$2" "$HA_URL/api/services/$1" >/dev/null; }
ha media_player/volume_set "{\"entity_id\":\"$P\",\"volume_level\":$VOL}"
ha music_assistant/play_media "{\"entity_id\":\"$P\",\"media_id\":\"$Q\",\"media_type\":\"track\",\"enqueue\":\"replace\"}"
for i in $(seq 1 30); do
    s=$(curl -s -m 5 -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/states/$P" | python3 -c "import sys,json; print(json.load(sys.stdin)['state'])")
    [ "$s" = playing ] && break; sleep 1
done
sleep ${CONVERGE_S:-10}   # let the canceller converge
PIPEWIRE_NODE=razer_dmic arecord -q -D pipewire -f S16_LE -r 48000 -c 1 -d 10 /tmp/aec_raw.wav &
PIPEWIRE_NODE=razer_aec_source arecord -q -D pipewire -f S16_LE -r 48000 -c 1 -d 10 /tmp/aec_out.wav
wait
ha media_player/media_pause "{\"entity_id\":\"$P\"}"
python3 - <<'EOF'
import wave, numpy as np
def lvl(p):
    w = wave.open(p); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float) / 32768
    x = x[48000:]                        # skip start-up
    return 20 * np.log10(x.std() + 1e-9)
r0, o0 = lvl("/tmp/aec_raw0.wav"), lvl("/tmp/aec_out0.wav")
r, o = lvl("/tmp/aec_raw.wav"), lvl("/tmp/aec_out.wav")
print(f"silence : raw {r0:.1f} dBFS | cancelled {o0:.1f} dBFS")
print(f"music   : raw {r:.1f} dBFS | cancelled {o:.1f} dBFS")
print(f"music above noise: raw {r - r0:+.1f} dB, cancelled {o - o0:+.1f} dB -> echo removed {(r - r0) - (o - o0):.1f} dB")
EOF
