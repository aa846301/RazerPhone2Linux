#!/usr/bin/env python3
"""Wake-word ("嘿賈伯斯") benchmark with sherpa-onnx open-vocabulary KWS.

Positives: TTS renditions of the wake word (optionally with a command after it).
Negatives: every test command sentence (no wake word) concatenated into one
long stream, plus near-miss phrases. Reports hits, false alarms per hour of
negative audio and CPU real-time factor. Synthetic audio only; real far-field
recordings are still required before any accuracy claim.
"""
import glob
import json
import os
import sys
import time
import wave

import numpy as np
import sherpa_onnx
from pypinyin import Style, pinyin

M = os.path.expanduser("~/voice/models")
B = os.path.expanduser("~/voice/bench")
KWS_DIR = [d for d in glob.glob(f"{M}/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-*") if os.path.isdir(d)][0]


def ppinyin_tokens(text):
    ini = pinyin(text, style=Style.INITIALS, strict=False)
    fin = pinyin(text, style=Style.FINALS_TONE, strict=False)
    out = []
    for i, f in zip(ini, fin):
        if i[0]:
            out.append(i[0])
        out.append(f[0])
    return out


def write_keywords(words, path):
    tokens = set(l.split()[0] for l in open(f"{KWS_DIR}/tokens.txt", encoding="utf-8"))
    with open(path, "w", encoding="utf-8") as f:
        for w in words:
            t = ppinyin_tokens(w)
            missing = [x for x in t if x not in tokens]
            if missing:
                print("WARN tokens missing for", w, missing)
            f.write(" ".join(t) + f" @{w}\n")
            print("keyword", w, "->", " ".join(t))


def read_wav16k(p):
    with wave.open(p) as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    if sr != 16000:  # linear resample is enough for a benchmark
        n = int(len(x) * 16000 / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)
    return x


def spotter(kw_file, threshold, score, threads=1):
    enc = glob.glob(f"{KWS_DIR}/encoder-*.int8.onnx")[0]
    dec = glob.glob(f"{KWS_DIR}/decoder-*.onnx")[0]
    joi = glob.glob(f"{KWS_DIR}/joiner-*.int8.onnx")[0]
    return sherpa_onnx.KeywordSpotter(tokens=f"{KWS_DIR}/tokens.txt", encoder=enc, decoder=dec, joiner=joi,
                                      num_threads=threads, keywords_file=kw_file, keywords_score=score,
                                      keywords_threshold=threshold, max_active_paths=4)


def run(kws, x):
    s = kws.create_stream()
    hits = []
    t0 = time.time()
    step = 1600  # 100 ms chunks, like a live microphone
    for i in range(0, len(x), step):
        s.accept_waveform(16000, x[i:i + step])
        while kws.is_ready(s):
            kws.decode_stream(s)
            r = kws.get_result(s)
            if r:
                hits.append((round(i / 16000, 1), r))
                kws.reset_stream(s)
    s.accept_waveform(16000, np.zeros(8000, dtype=np.float32))
    s.input_finished()
    while kws.is_ready(s):
        kws.decode_stream(s)
        r = kws.get_result(s)
        if r:
            hits.append((round(len(x) / 16000, 1), r))
            kws.reset_stream(s)
    return hits, time.time() - t0


def main():
    tts_dir = sorted(glob.glob(f"{B}/kws-tts-*"))
    neg_sets = sorted(glob.glob(f"{B}/tts-*"))
    kw = f"{B}/keywords.txt"
    write_keywords(["嘿賈伯斯"], kw)
    report = {}
    for threshold in (0.15, 0.25, 0.35):
        for score in (1.0, 2.0):
            kws = spotter(kw, threshold, score)
            pos = tot = 0
            for d in tts_dir:
                for p in sorted(glob.glob(f"{d}/*.wav")):
                    hits, _ = run(kws, np.concatenate([np.zeros(8000, np.float32), read_wav16k(p)]))
                    tot += 1
                    pos += bool(hits)
            neg_audio = fa = 0.0
            cpu = 0.0
            for d in neg_sets:
                x = np.concatenate([np.concatenate([read_wav16k(p), np.zeros(8000, np.float32)])
                                    for p in sorted(glob.glob(f"{d}/*.wav"))])
                hits, dt = run(kws, x)
                fa += len(hits)
                neg_audio += len(x) / 16000
                cpu += dt
            key = f"thr={threshold},score={score}"
            report[key] = {"detected": f"{pos}/{tot}", "false_alarms": int(fa), "negative_audio_min": round(neg_audio / 60, 1),
                           "fa_per_hour": round(fa / max(neg_audio, 1) * 3600, 1), "rtf_1thread": round(cpu / max(neg_audio, 1), 4)}
            print(key, report[key], flush=True)
    with open(f"{B}/kws-report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
