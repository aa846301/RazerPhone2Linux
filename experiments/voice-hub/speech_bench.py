#!/usr/bin/env python3
"""TTS + ASR benchmark on the phone (sherpa-onnx, CPU only).

1. tts:  synthesise every test sentence with each available Chinese TTS model
         into wav files (never played back), recording RTF and wall time.
2. asr:  transcribe those wavs (and any real recordings) with each ASR model,
         reporting RTF, load time and CER after numeral normalisation.

Synthetic speech is NOT a substitute for real zh-TW speakers; results only
measure speed and number/device-name handling on clean audio.
"""
import argparse
import glob
import json
import os
import re
import time
import wave

import numpy as np
import sherpa_onnx

M = os.path.expanduser("~/voice/models")
HERE = os.path.dirname(os.path.abspath(__file__))

CN = {"零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def cn_num(s):
    def conv(m):
        t = m.group(0)
        if t == "十":
            return "10"
        if "十" in t:
            a, b = t.split("十", 1)
            return str((CN.get(a, 1) if a else 1) * 10 + (CN.get(b, 0) if b else 0))
        if len(t) == 2 and all(c in CN for c in t):  # 二六 -> 26
            return str(CN[t[0]] * 10 + CN[t[1]])
        return str(CN[t]) if len(t) == 1 else t
    s = re.sub(r"百分之([零一二兩三四五六七八九十]+)", lambda m: cn_num(m.group(1)) + "%", s)
    return re.sub(r"[一二兩三四五六七八九]?十[一二三四五六七八九]?|[一二兩三四五六七八九]{2}(?=度|$)|[一二兩三四五六七八九](?=度)", conv, s)


try:  # SenseVoice/Paraformer emit Simplified Chinese; the hub works in zh-TW
    import opencc
    _S2T = opencc.OpenCC("s2twp")
except Exception:  # pragma: no cover
    _S2T = None


def to_tw(s):
    return _S2T.convert(s) if _S2T else s


def norm(s):
    s = cn_num(to_tw(s))
    s = s.replace("％", "%")
    return re.sub(r"[\s，。、！？,.!?：:；;「」\"'~～]", "", s).lower()


def cer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)], max(len(r), 1)


def read_wav(p):
    with wave.open(p) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
        return x, w.getframerate()


def write_wav(p, samples, sr):
    x = np.clip(np.asarray(samples), -1, 1)
    with wave.open(p, "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(sr)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def tts_models(threads):
    cands = {}
    d = f"{M}/matcha-icefall-zh-baker"
    if os.path.isdir(d) and os.path.exists(f"{M}/vocos-22khz-univ.onnx"):
        cands["matcha-zh-baker"] = sherpa_onnx.OfflineTtsModelConfig(
            matcha=sherpa_onnx.OfflineTtsMatchaModelConfig(
                acoustic_model=f"{d}/model-steps-3.onnx", vocoder=f"{M}/vocos-22khz-univ.onnx",
                lexicon=f"{d}/lexicon.txt", tokens=f"{d}/tokens.txt", dict_dir=f"{d}/dict"),
            num_threads=threads)
    d = f"{M}/vits-piper-zh_CN-huayan-medium"
    if os.path.isdir(d):
        cands["piper-zh-huayan"] = sherpa_onnx.OfflineTtsModelConfig(
            vits=sherpa_onnx.OfflineTtsVitsModelConfig(
                model=glob.glob(f"{d}/*.onnx")[0], tokens=f"{d}/tokens.txt", data_dir=f"{d}/espeak-ng-data"),
            num_threads=threads)
    d = f"{M}/kokoro-int8-multi-lang-v1_1"
    if os.path.isdir(d):
        cands["kokoro-int8-v1.1"] = sherpa_onnx.OfflineTtsModelConfig(
            kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                model=f"{d}/model.int8.onnx", voices=f"{d}/voices.bin", tokens=f"{d}/tokens.txt",
                data_dir=f"{d}/espeak-ng-data", dict_dir=f"{d}/dict",
                lexicon=f"{d}/lexicon-us-en.txt,{d}/lexicon-zh.txt"),
            num_threads=threads)
    return cands


def asr_models(threads):
    cands = {}
    d = f"{M}/sensevoice"  # model.int8.onnx + tokens.txt from the 2024-07-17 release
    if os.path.exists(f"{d}/model.int8.onnx"):
        cands["sensevoice-small-int8"] = lambda d=d: sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=f"{d}/model.int8.onnx", tokens=f"{d}/tokens.txt", num_threads=threads, use_itn=True, language="zh")
    d = f"{M}/sherpa-onnx-paraformer-zh-small-2024-03-09"
    if os.path.exists(f"{d}/model.int8.onnx"):
        cands["paraformer-zh-small-int8"] = lambda d=d: sherpa_onnx.OfflineRecognizer.from_paraformer(
            paraformer=f"{d}/model.int8.onnx", tokens=f"{d}/tokens.txt", num_threads=threads)
    return cands


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", choices=["tts", "asr"])
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--out", default=os.path.expanduser("~/voice/bench"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    cases = [json.loads(l) for l in open(f"{HERE}/tests.jsonl", encoding="utf-8") if l.strip()]
    report = {}
    if args.stage == "tts":
        for name, mc in tts_models(args.threads).items():
            t0 = time.time()
            tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(model=mc, max_num_sentences=1))
            load = time.time() - t0
            os.makedirs(f"{args.out}/tts-{name}", exist_ok=True)
            gen, dur = 0.0, 0.0
            for c in cases:
                t0 = time.time()
                a = tts.generate(c["text"], sid=0 if "kokoro" not in name else 45, speed=1.0)
                gen += time.time() - t0
                dur += len(a.samples) / a.sample_rate
                write_wav(f'{args.out}/tts-{name}/{c["id"]:02d}.wav', a.samples, a.sample_rate)
            report[name] = {"load_s": round(load, 2), "gen_s": round(gen, 2), "audio_s": round(dur, 2),
                            "rtf": round(gen / dur, 3), "sentences": len(cases)}
            # wake-word positives for kws_bench.py (never played back)
            kd = f"{args.out}/kws-tts-{name}"
            os.makedirs(kd, exist_ok=True)
            sids = [0] if "kokoro" not in name else [45, 46, 50, 55]
            for sid in sids:
                for speed in (0.85, 1.0, 1.2):
                    for i, t in enumerate(("嘿賈伯斯", "嘿，賈伯斯", "嘿賈伯斯，打開客廳主燈")):
                        try:
                            a = tts.generate(t, sid=sid, speed=speed)
                        except Exception as ex:  # unsupported sid
                            print("skip", name, sid, ex)
                            break
                        write_wav(f"{kd}/s{sid}-v{speed}-{i}.wav", a.samples, a.sample_rate)
            print(name, report[name], flush=True)
    else:
        sets = {os.path.basename(p): p for p in sorted(glob.glob(f"{args.out}/tts-*"))}
        for name, mk in asr_models(args.threads).items():
            t0 = time.time()
            rec = mk()
            load = time.time() - t0
            for sname, sdir in sets.items():
                errs = n = 0
                proc = audio = 0.0
                rows = []
                for c in cases:
                    p = f'{sdir}/{c["id"]:02d}.wav'
                    if not os.path.exists(p):
                        continue
                    x, sr = read_wav(p)
                    t0 = time.time()
                    s = rec.create_stream()
                    s.accept_waveform(sr, x)
                    rec.decode_stream(s)
                    proc += time.time() - t0
                    audio += len(x) / sr
                    e, l = cer(c["text"], s.result.text)
                    errs += e
                    n += l
                    rows.append({"id": c["id"], "ref": c["text"], "hyp": s.result.text, "hyp_tw": to_tw(s.result.text),
                                 "cer": round(e / l, 3)})
                key = f"{name}@{sname}"
                report[key] = {"load_s": round(load, 2), "rtf": round(proc / max(audio, 1e-9), 3),
                               "avg_decode_s": round(proc / max(len(rows), 1), 3), "cer": round(errs / max(n, 1), 4),
                               "exact": sum(r["cer"] == 0 for r in rows), "n": len(rows)}
                print(key, report[key], flush=True)
                with open(f"{args.out}/asr-{key}.json", "w", encoding="utf-8") as f:
                    json.dump(rows, f, ensure_ascii=False, indent=1)
    with open(f"{args.out}/{args.stage}-report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
