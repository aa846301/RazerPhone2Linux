#!/usr/bin/env python3
"""Wake-word tuning on a real recording of the user (normal voice, normal distance).

Grid: input gain (x1, x2, x4, x8, slow AGC) x keyword set (base, +variants) x threshold x score.
For each setting: wake words detected in the user recording, and false alarms on the negative speech sets
in ~/voice/bench/tts-* (TTS command sentences without the wake word, ~2.5 min).
Usage: kws_tune2.py user_rec.wav [expected_count]
"""
import glob
import os
import sys
import wave

import numpy as np
import sherpa_onnx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice import MODELS, SR, Decimator, _pinyin_tokens  # noqa: E402

KWS_DIR = [d for d in glob.glob(f"{MODELS}/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-*") if os.path.isdir(d)][0]
SETS = {
    "base": ["嘿賈伯斯"],
    "variants": ["嘿賈伯斯", "嘿賈博士", "嘿佳伯斯", "嘿家伯斯"],
}


def read16k(path):
    w = wave.open(path)
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
    sr = w.getframerate()
    if sr == 48000:
        return Decimator()(x)
    if sr != SR:
        n = int(len(x) * SR / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)
    return x


def agc(x, target=0.05, max_gain=16.0):
    """Slow AGC on 100 ms blocks: gain follows target / running RMS (attack 1 s, release 3 s)."""
    out = np.empty_like(x)
    g, rms = 1.0, target
    for i in range(0, len(x), 1600):
        b = x[i:i + 1600]
        r = float(np.sqrt(np.mean(b * b)) + 1e-6)
        rms = 0.9 * rms + 0.1 * r if r > rms else 0.97 * rms + 0.03 * r
        g = float(np.clip(target / rms, 1.0, max_gain))
        out[i:i + 1600] = np.clip(b * g, -1, 1)
    return out


def spotter(words, thr, score):
    kw = f"/tmp/kw_{abs(hash(tuple(words)))}.txt"
    with open(kw, "w", encoding="utf-8") as f:
        for w in words:
            f.write(" ".join(_pinyin_tokens(w)) + " @嘿賈伯斯\n")
    return sherpa_onnx.KeywordSpotter(
        tokens=f"{KWS_DIR}/tokens.txt", encoder=glob.glob(f"{KWS_DIR}/encoder-*.int8.onnx")[0],
        decoder=glob.glob(f"{KWS_DIR}/decoder-*.onnx")[0], joiner=glob.glob(f"{KWS_DIR}/joiner-*.int8.onnx")[0],
        num_threads=4, keywords_file=kw, keywords_score=score, keywords_threshold=thr, max_active_paths=4)


def count(k, x):
    s = k.create_stream()
    hits = []
    for i in range(0, len(x), 1600):
        s.accept_waveform(SR, x[i:i + 1600])
        while k.is_ready(s):
            k.decode_stream(s)
            if k.get_result(s):
                hits.append(round(i / SR, 1))
                k.reset_stream(s)
    return hits


user = read16k(sys.argv[1])
expected = int(sys.argv[2]) if len(sys.argv) > 2 else None
print("user rec", round(len(user) / SR, 1), "s; level per 2 s (dBFS):",
      [round(20 * np.log10(user[i:i + 2 * SR].std() + 1e-9)) for i in range(SR, len(user), 2 * SR)])
neg = np.concatenate([np.concatenate([read16k(p), np.zeros(8000, np.float32)])
                      for d in sorted(glob.glob(os.path.expanduser("~/voice/bench/tts-*")))
                      for p in sorted(glob.glob(f"{d}/*.wav"))])
print("negatives", round(len(neg) / SR / 60, 1), "min")
gains = {"x1": lambda v: v, "x4": lambda v: np.clip(v * 4, -1, 1), "agc": agc}
rows = []
for gname, gf in gains.items():
    u, n = gf(user), gf(neg)
    for sname, words in SETS.items():
        for thr in (0.1, 0.2):
            for score in (3.0, 4.0):
                k = spotter(words, thr, score)
                hu, hn = count(k, u), count(k, n)
                rows.append((len(hu), -len(hn), gname, sname, thr, score, hu, len(hn)))
                print(f"{gname:<4} {sname:<8} thr {thr:<5} score {score}: user {len(hu)} {hu}  false {len(hn)}",
                      flush=True)
print("\nBEST (most detections, then fewest false alarms):")
for r in sorted(rows, key=lambda r: (r[0], r[1]), reverse=True)[:8]:
    print(f"  {r[2]} {r[3]} thr {r[4]} score {r[5]}: user {r[0]}{'/' + str(expected) if expected else ''}"
          f" false {r[7]}")
