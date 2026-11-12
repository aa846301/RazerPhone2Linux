"""Voice pipeline for the Razer hub agent: DMIC -> 16 kHz -> wake word (sherpa-onnx KWS, 「嘿賈伯斯」)
-> utterance capture (silero VAD) -> SenseVoice ASR -> Traditional Chinese text.

A single `arecord` process owns the capture device (hw:0,1, 48 kHz mono, set up by razer-mic-setup).
The wake word runs continuously on one thread; `listen()` (UI mic button) skips the wake word.
States reported through on_state(state, text): idle | listening | thinking (ASR) ; the agent reports the
command result itself.
"""
import glob
import os
import subprocess
import threading
import time
import wave

import numpy as np
import sherpa_onnx

MODELS = os.path.expanduser("~/voice/models")
SR = 16000
WAKE_WORD = "嘿賈伯斯"


def _lowpass_taps(n=63, cutoff=7000.0, fs=48000.0):
    m = np.arange(n) - (n - 1) / 2
    h = np.sinc(2 * cutoff / fs * m) * np.hamming(n)
    return (h / h.sum()).astype(np.float32)


class Decimator:
    """48 kHz -> 16 kHz with a windowed-sinc low-pass; keeps filter history across chunks."""

    def __init__(self):
        self.h = _lowpass_taps()
        self.hist = np.zeros(len(self.h) - 1, np.float32)
        self.phase = 0

    def __call__(self, x):
        buf = np.concatenate([self.hist, x])
        y = np.convolve(buf, self.h, mode="valid")
        self.hist = buf[-(len(self.h) - 1):]
        out = y[self.phase::3]
        self.phase = (self.phase - len(y)) % 3
        return out


def _pinyin_tokens(text):
    from pypinyin import Style, pinyin
    ini = pinyin(text, style=Style.INITIALS, strict=False)
    fin = pinyin(text, style=Style.FINALS_TONE, strict=False)
    out = []
    for i, f in zip(ini, fin):
        if i[0]:
            out.append(i[0])
        out.append(f[0])
    return out


CHIME_VERSION = 5   # bump to regenerate cached chimes
CHIME_SR = 48000
CHIME_PEAK = 0.4   # -8 dBFS (user: style 4 at -4 dBFS was a bit loud, 2026-11-11)


def _env(t, attack=0.012, tau=0.3):
    return np.minimum(1, t / attack) * np.exp(-t / tau)


def _voice(style, hz, t):
    """One note of the given timbre (unit amplitude-ish)."""
    w = 2 * np.pi * hz * t
    if style == "dual":        # DTMF-like: the note plus a perfect fifth sounding together
        return (np.sin(w) + 0.8 * np.sin(1.5 * w)) * _env(t, 0.008, 0.28)
    if style == "marimba":     # struck bar: strong fundamental, 4th partial decaying fast, a little 10th
        return (np.sin(w) * _env(t, 0.004, 0.32) + 0.35 * np.sin(4 * w) * _env(t, 0.002, 0.06)
                + 0.08 * np.sin(10 * w) * _env(t, 0.001, 0.02))
    if style == "glass":       # FM bell: inharmonic modulator (ratio 1.4) whose index decays
        idx = 2.2 * np.exp(-t / 0.18)
        return np.sin(w + idx * np.sin(1.4 * w)) * _env(t, 0.003, 0.45)
    # "triad": soft triangle-ish tone (odd harmonics, steep roll-off)
    return (np.sin(w) - np.sin(3 * w) / 9 + np.sin(5 * w) / 25) * _env(t, 0.015, 0.35)


def render_chime(style, notes, length):
    """notes: [(hz, start_s, gain)] -> float32 mono at CHIME_SR, peak -4 dBFS, with a soft echo."""
    n = int(CHIME_SR * length)
    x = np.zeros(n)
    for hz, start, g in notes:
        i0 = int(CHIME_SR * start)
        t = np.arange(n - i0) / CHIME_SR
        x[i0:] += g * _voice(style, hz, t)
    d1 = int(CHIME_SR * 0.09)
    x[d1:] += 0.18 * x[:-d1]
    x *= np.minimum(1, (n - np.arange(n)) / (CHIME_SR * 0.05))
    return (x / np.abs(x).max() * CHIME_PEAK).astype(np.float32)


# Note sets in the warm 390-1000 Hz range the phone speakers reproduce well.
_G4, _A4, _C5, _D5, _E5, _G5, _E4 = 392.0, 440.0, 523.25, 587.33, 659.25, 783.99, 329.63
CHIME_NOTES = {
    "start": ([(_G4, 0.00, 1.0), (_C5, 0.10, 0.9)], 0.8),
    "ok": ([(_C5, 0.00, 0.8), (_E5, 0.07, 0.8), (_G5, 0.14, 0.7)], 0.9),
    "fail": ([(_A4, 0.00, 1.0), (_E4, 0.15, 0.9)], 0.9),
}
CHIME_STYLES = ("dual", "marimba", "glass", "triad")


def write_wav(path, x):
    st = (np.repeat(x[:, None], 2, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(CHIME_SR)
        w.writeframes(st.tobytes())


def make_chimes(d, style=None):
    """Chimes for the chosen style (HUB_CHIME_STYLE, default 'triad'), written once per style/version."""
    style = style or os.environ.get("HUB_CHIME_STYLE", "triad")
    if style not in CHIME_STYLES:
        style = "triad"
    os.makedirs(d, exist_ok=True)
    paths = {k: f"{d}/{style}-{k}-v{CHIME_VERSION}.wav" for k in CHIME_NOTES}
    for k, p in paths.items():
        if not os.path.exists(p):
            notes, length = CHIME_NOTES[k]
            write_wav(p, render_chime(style, notes, length))
    return paths


class Voice:
    # keywords_score 3.0: on a real recording (user's voice, ~-47 dBFS at the DMIC) only score 3.0 fired; the
    # thresholds 0.05-0.25 and a x4 gain made no difference (hub-agent/kws_tune.py, 2026-11-11). The old 1.0 came
    # from TTS-only tests. False alarms with 3.0 are not measured yet.
    def __init__(self, log, on_state, on_utterance, kws_threshold=0.25, kws_score=3.0):
        self.log = log
        self.on_state = on_state            # (state, text)
        self.on_utterance = on_utterance    # (text) -> None, called on a worker thread
        self.chimes = make_chimes(os.path.expanduser("~/.cache/razer-hub/chimes"))
        try:
            from light import LightSensor
            self.light = LightSensor(log)
        except Exception as e:
            log(f"light sensor unavailable: {e!r}")
            self.light = None
        self._listen_req = threading.Event()
        self._cancel = threading.Event()
        self.busy = False
        self.mute_until = 0.0               # ignore mic input while our own chime plays

        kws_dir = [d for d in glob.glob(f"{MODELS}/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-*") if os.path.isdir(d)][0]
        kw_file = os.path.expanduser("~/.cache/razer-hub/keywords.txt")
        os.makedirs(os.path.dirname(kw_file), exist_ok=True)
        with open(kw_file, "w", encoding="utf-8") as f:
            f.write(" ".join(_pinyin_tokens(WAKE_WORD)) + f" @{WAKE_WORD}\n")
        self.kws = sherpa_onnx.KeywordSpotter(
            tokens=f"{kws_dir}/tokens.txt",
            encoder=glob.glob(f"{kws_dir}/encoder-*.int8.onnx")[0],
            decoder=glob.glob(f"{kws_dir}/decoder-*.onnx")[0],
            joiner=glob.glob(f"{kws_dir}/joiner-*.int8.onnx")[0],
            num_threads=1, keywords_file=kw_file, keywords_score=kws_score,
            keywords_threshold=kws_threshold, max_active_paths=4)
        vcfg = sherpa_onnx.VadModelConfig()
        vcfg.silero_vad.model = f"{MODELS}/silero_vad.onnx"
        vcfg.silero_vad.threshold = 0.5
        vcfg.silero_vad.min_silence_duration = 0.6
        vcfg.silero_vad.min_speech_duration = 0.25
        vcfg.silero_vad.max_speech_duration = 12
        vcfg.sample_rate = SR
        vcfg.num_threads = 1
        self.vad_cfg = vcfg
        t0 = time.time()
        self.asr = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=f"{MODELS}/sensevoice/model.int8.onnx", tokens=f"{MODELS}/sensevoice/tokens.txt",
            num_threads=4, use_itn=True, language="zh")
        self.log(f"voice models loaded in {time.time() - t0:.1f}s")
        try:
            import opencc
            self.s2t = opencc.OpenCC("s2twp").convert
        except Exception:
            self.s2t = lambda s: s
        threading.Thread(target=self._run, name="voice", daemon=True).start()

    # ------------------------------------------------------------------ public
    def listen(self):
        if not self.busy:
            self._listen_req.set()

    def cancel(self):
        self._cancel.set()

    def quiet_now(self):
        """No chimes when the room is dark (ambient light sensor; user: dark room = asleep, light on = awake).
        Without a fresh light reading, fall back to HUB_QUIET_HOURS="23-8" (local time, wraps midnight)."""
        light = getattr(self, "light", None)
        if light is not None and light.fresh():
            return light.dark
        spec = os.environ.get("HUB_QUIET_HOURS", "23-8")
        try:
            a, b = (int(v) for v in spec.split("-"))
        except ValueError:
            return False
        h = time.localtime().tm_hour
        return (a <= h or h < b) if a > b else (a <= h < b)

    @staticmethod
    def log_only_now():
        """HUB_WAKE_LOG_ONLY_UNTIL=YYYY-MM-DDTHH:MM: until then a wake word is only counted (false-wake
        measurement while the user sleeps); the mic button still works normally."""
        until = os.environ.get("HUB_WAKE_LOG_ONLY_UNTIL")
        if not until:
            return False
        try:
            return time.time() < time.mktime(time.strptime(until, "%Y-%m-%dT%H:%M"))
        except ValueError:
            return False

    def play(self, name):
        if self.quiet_now():
            return
        p = self.chimes.get(name)
        if p:
            self.mute_until = time.time() + 0.9   # chimes are up to 0.85 s
            subprocess.Popen(["pw-play", p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # ----------------------------------------------------------------- private
    def _mic(self):
        """Echo-cancelled mic from PipeWire (razer_aec_source, see pipewire-razer-aec.conf) so the wake word works
        while the speakers play music; HUB_MIC_DEVICE=hw:0,1 reads the raw DMIC directly instead."""
        subprocess.run(["sudo", "-n", "/usr/local/sbin/razer-mic-setup", "mono", "96"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dev = os.environ.get("HUB_MIC_DEVICE", "pipewire")
        env = dict(os.environ)
        if dev == "pipewire":
            env["PIPEWIRE_NODE"] = os.environ.get("HUB_MIC_NODE", "razer_aec_source")
        self.log(f"microphone: {dev} {env.get('PIPEWIRE_NODE', '')}")
        return subprocess.Popen(["arecord", "-q", "-D", dev, "-f", "S16_LE", "-r", "48000", "-c", "1",
                                 "-t", "raw", "--buffer-time=200000"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)

    def _run(self):
        while True:
            try:
                self._loop()
            except Exception as e:
                self.log(f"voice loop error: {e!r}")
            self.busy = False
            self.on_state("idle", "")
            time.sleep(3)

    def _loop(self):
        proc = self._mic()
        dec = Decimator()
        kstream = self.kws.create_stream()
        chunk = 4800 * 2  # 100 ms of 48 kHz S16 mono
        self.log("microphone open, waiting for wake word")
        try:
            while True:
                raw = proc.stdout.read(chunk)
                if not raw or len(raw) < chunk:
                    raise RuntimeError(f"arecord stopped: {proc.stderr.read().decode(errors='replace')[-200:]}")
                x = dec(np.frombuffer(raw, np.int16).astype(np.float32) / 32768)
                woke = False
                if time.time() >= self.mute_until:
                    kstream.accept_waveform(SR, x)
                    while self.kws.is_ready(kstream):
                        self.kws.decode_stream(kstream)
                        if self.kws.get_result(kstream):
                            woke = True
                            self.kws.reset_stream(kstream)
                if woke and self.log_only_now():
                    self.log("wake word (log only)")
                    with open(os.path.expanduser("~/.local/state/razer-hub/wake-log.txt"), "a") as f:
                        f.write(time.strftime("%F %T") + " wake word (not acted on)\n")
                    woke = False
                if (woke or self._listen_req.is_set()) and not self.busy:
                    self._listen_req.clear()
                    self.log("wake word" if woke else "listen (button)")
                    self._utterance(proc, dec)
                    kstream = self.kws.create_stream()
        finally:
            proc.kill()

    def _utterance(self, proc, dec):
        self.busy = True
        self._cancel.clear()
        self.on_state("listening", "正在聆聽…")
        self.play("start")
        vad = sherpa_onnx.VoiceActivityDetector(self.vad_cfg, buffer_size_in_seconds=30)
        t0 = time.time()
        speech = []
        started = False
        chunk = 4800 * 2
        pending = np.zeros(0, np.float32)
        while True:
            raw = proc.stdout.read(chunk)
            if not raw or len(raw) < chunk:
                raise RuntimeError("arecord stopped while listening")
            x = dec(np.frombuffer(raw, np.int16).astype(np.float32) / 32768)
            if time.time() < self.mute_until:
                continue                     # skip our own start chime
            pending = np.concatenate([pending, x])
            while len(pending) >= 512:       # silero window
                vad.accept_waveform(pending[:512])
                pending = pending[512:]
            if vad.is_speech_detected():
                started = True
            while not vad.empty():
                speech.append(np.array(vad.front.samples, np.float32))
                vad.pop()
            el = time.time() - t0
            if self._cancel.is_set():
                self.busy = False
                self.on_state("idle", "")
                return
            if speech and not vad.is_speech_detected():
                break                        # one complete utterance
            if not started and el > 6:
                self.busy = False
                self.on_state("done", "沒有聽到指令")
                self.play("fail")
                return
            if el > 15:
                vad.flush()
                while not vad.empty():
                    speech.append(np.array(vad.front.samples, np.float32))
                    vad.pop()
                break
        audio = np.concatenate(speech) if speech else np.zeros(SR // 2, np.float32)
        self.on_state("thinking", "理解中…")
        t1 = time.time()
        s = self.asr.create_stream()
        s.accept_waveform(SR, audio)
        self.asr.decode_stream(s)
        text = self.s2t(s.result.text.strip())
        self.log(f"ASR {len(audio) / SR:.1f}s audio -> {text!r} in {time.time() - t1:.2f}s")
        threading.Thread(target=self._finish, args=(text,), daemon=True).start()

    def _finish(self, text):
        try:
            self.on_utterance(text)
        finally:
            self.busy = False
