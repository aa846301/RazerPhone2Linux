#!/usr/bin/env python3
"""Offline wake-word check on a real recording: ASR transcript (what was actually heard), per-second level,
and KWS hits for a grid of thresholds/scores, with and without gain. Usage: kws_tune.py rec.wav"""
import glob
import os
import sys
import wave

import numpy as np
import sherpa_onnx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice import MODELS, SR, WAKE_WORD, Decimator, _pinyin_tokens  # noqa: E402

w = wave.open(sys.argv[1])
x48 = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
x = Decimator()(x48)
print("seconds", round(len(x) / SR, 1), "level per second (dBFS):",
      [round(20 * np.log10(x[i:i + SR].std() + 1e-9)) for i in range(0, len(x), SR)])
asr = sherpa_onnx.OfflineRecognizer.from_sense_voice(model=f"{MODELS}/sensevoice/model.int8.onnx",
                                                     tokens=f"{MODELS}/sensevoice/tokens.txt", num_threads=4,
                                                     use_itn=True, language="zh")
s = asr.create_stream()
s.accept_waveform(SR, x[SR // 2:])
asr.decode_stream(s)
print("ASR heard:", s.result.text)
kd = [d for d in glob.glob(f"{MODELS}/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-*") if os.path.isdir(d)][0]
print("keyword tokens:", " ".join(_pinyin_tokens(WAKE_WORD)))
with open("/tmp/kw_tune.txt", "w", encoding="utf-8") as f:
    f.write(" ".join(_pinyin_tokens(WAKE_WORD)) + f" @{WAKE_WORD}\n")
for gain in (1, 4):
    for thr in (0.05, 0.1, 0.15, 0.25):
        for score in (1.0, 2.0, 3.0):
            k = sherpa_onnx.KeywordSpotter(tokens=f"{kd}/tokens.txt",
                                           encoder=glob.glob(f"{kd}/encoder-*.int8.onnx")[0],
                                           decoder=glob.glob(f"{kd}/decoder-*.onnx")[0],
                                           joiner=glob.glob(f"{kd}/joiner-*.int8.onnx")[0], num_threads=2,
                                           keywords_file="/tmp/kw_tune.txt", keywords_score=score,
                                           keywords_threshold=thr, max_active_paths=4)
            st = k.create_stream()
            hits = []
            y = np.clip(x * gain, -1, 1)
            for i in range(0, len(y), 1600):
                st.accept_waveform(SR, y[i:i + 1600])
                while k.is_ready(st):
                    k.decode_stream(st)
                    if k.get_result(st):
                        hits.append(round(i / SR, 1))
                        k.reset_stream(st)
            print(f"gain x{gain} thr {thr:<5} score {score}: {len(hits)} hits {hits}")
