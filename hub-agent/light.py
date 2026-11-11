"""Ambient light (STK3x1x behind the SLPI sensor DSP) via libssc's `ssccli --sensor light`.

Needs hexagonrpcd-sdsp.service (serves the SLPI its sensor configuration). A background thread keeps one
ssccli process running, smooths the lux readings and tracks "dark" with hysteresis and a hold time, so a
passing shadow does not mute the hub and a lamp switched on un-mutes it within seconds.
Env: HUB_DARK_LUX (default 5), HUB_BRIGHT_LUX (default 12), HUB_DARK_HOLD_S (default 30).
"""
import os
import re
import subprocess
import threading
import time

LUX_RE = re.compile(r"([0-9.]+)\s*Lux")


class LightSensor:
    def __init__(self, log):
        self.log = log
        self.dark_lux = float(os.environ.get("HUB_DARK_LUX", "5"))
        self.bright_lux = float(os.environ.get("HUB_BRIGHT_LUX", "12"))
        self.hold = float(os.environ.get("HUB_DARK_HOLD_S", "30"))
        self.lux = None              # smoothed value
        self.updated = 0.0           # time of the last reading
        self.dark = False
        self._below_since = None
        threading.Thread(target=self._run, name="light", daemon=True).start()

    def fresh(self):
        return self.lux is not None and time.time() - self.updated < 60

    def _feed(self, v):
        now = time.time()
        self.lux = v if self.lux is None else 0.7 * self.lux + 0.3 * v
        self.updated = now
        if not self.dark:
            if self.lux < self.dark_lux:
                self._below_since = self._below_since or now
                if now - self._below_since >= self.hold:
                    self.dark = True
                    self.log(f"light: dark ({self.lux:.1f} lux) -> chimes off")
            else:
                self._below_since = None
        elif self.lux > self.bright_lux:
            self.dark = False
            self._below_since = None
            self.log(f"light: bright ({self.lux:.1f} lux) -> chimes on")

    def _run(self):
        while True:
            try:
                p = subprocess.Popen(["ssccli", "--sensor", "light", "--timeout", "31536000"],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                for line in p.stdout:
                    m = LUX_RE.search(line)
                    if m:
                        self._feed(float(m.group(1)))
                p.wait()
                self.log(f"light: ssccli exited rc={p.returncode}")
            except FileNotFoundError:
                self.log("light: ssccli not installed; using quiet hours only")
                return
            except Exception as e:
                self.log(f"light: {e!r}")
            time.sleep(10)
