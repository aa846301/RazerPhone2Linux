#!/usr/bin/env python3
"""Write one preview WAV with every chime style: per style start, ok, fail, then 2 s of silence.
Usage: chime_preview.py out.wav [style ...]"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from voice import CHIME_NOTES, CHIME_SR, CHIME_STYLES, render_chime, write_wav  # noqa: E402

styles = sys.argv[2:] or list(CHIME_STYLES)
gap, pause = np.zeros(int(CHIME_SR * 0.35), np.float32), np.zeros(int(CHIME_SR * 2.0), np.float32)
parts = []
for s in styles:
    for k in ("start", "ok", "fail"):
        notes, length = CHIME_NOTES[k]
        parts += [render_chime(s, notes, length), gap]
    parts.append(pause)
    print("style", len(parts) and s)
write_wav(sys.argv[1], np.concatenate(parts))
