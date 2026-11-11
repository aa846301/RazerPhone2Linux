#!/usr/bin/env python3
"""Per-command latency of the slot LLM with the prefix cache hit, plus CPU/GPU frequencies sampled every 50 ms.

Usage: llm_freq_bench.py <url> <label> [n=10]
The first call builds the prefix cache (reported separately); the next n calls are cache hits.
Output: one line per call and a summary with mean frequencies during the calls.
"""
import os
import statistics
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.expanduser("~/voice"))
import devices  # noqa: E402
from ha import HA  # noqa: E402
from hub_agent import load_env  # noqa: E402
from nlu_slots import SlotParser  # noqa: E402

URL, LABEL = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 10
GPU = "/sys/class/devfreq/5000000.gpu/cur_freq"
CPU = {"little": "/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq",
       "big": "/sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq"}
SENTENCES = ["我要出門了", "好熱喔", "房間好暗", "有點冷", "太亮了", "我要睡了",
             "幫我弄涼一點", "客廳暗暗的", "今天好悶", "準備看電影"]


def rd(p):
    with open(p) as f:
        return int(f.read())


samples = []                       # (t, gpu_mhz, little_mhz, big_mhz)
stop = threading.Event()


def sampler():
    while not stop.is_set():
        samples.append((time.time(), rd(GPU) / 1e6, rd(CPU["little"]) / 1e3, rd(CPU["big"]) / 1e3))
        time.sleep(0.05)


env = load_env(os.path.expanduser("~/.config/razer-voice/ha.env"))
ha = HA(env["HA_URL"], env["HA_TOKEN"], lambda m: None, lambda: None)
t0 = time.time()
while not ha.snapshot()[4] and time.time() - t0 < 15:
    time.sleep(0.2)
sp = SlotParser(devices.nlu_home(ha.snapshot()), URL, compact=True)

threading.Thread(target=sampler, daemon=True).start()
t = time.time()
_, tm = sp.ask("你好")
print(f"[{LABEL}] prefix build {time.time() - t:.1f}s reused={tm.get('reused')}", flush=True)
time.sleep(1.0)

rows = []
for i in range(N):
    s = SENTENCES[i % len(SENTENCES)]
    a = time.time()
    _, tm = sp.ask(s)
    b = time.time()
    win = [x for x in samples if a <= x[0] <= b]
    g = statistics.mean(x[1] for x in win) if win else 0
    lb = statistics.mean(x[3] for x in win) if win else 0
    gmax = sum(1 for x in win if x[1] >= 700) / max(len(win), 1)
    rows.append((b - a, tm.get("prompt_ms", 0), tm.get("predicted_ms", 0), tm.get("predicted_n", 0), g, lb, gmax,
                 tm.get("reused")))
    print(f"  {s:<8} {b - a:5.2f}s read {tm.get('prompt_ms', 0) / 1000:4.2f}s gen {tm.get('predicted_ms', 0) / 1000:4.2f}s "
          f"({tm.get('predicted_n', 0)} tok) reused={tm.get('reused')} | GPU {g:4.0f} MHz (max {gmax:.0%}) "
          f"big CPU {lb:4.0f} MHz", flush=True)
    time.sleep(1.5)                # idle gap like real use, lets the governors drop again
stop.set()
w = [r[0] for r in rows]
print(f"[{LABEL}] SUMMARY n={N} wall median {statistics.median(w):.2f}s mean {statistics.mean(w):.2f}s "
      f"min {min(w):.2f}s max {max(w):.2f}s | read mean {statistics.mean(r[1] for r in rows) / 1000:.2f}s "
      f"gen mean {statistics.mean(r[2] for r in rows) / 1000:.2f}s "
      f"gen tok/s {sum(r[3] for r in rows) / max(sum(r[2] for r in rows) / 1000, 1e-9):.1f} | "
      f"GPU mean {statistics.mean(r[4] for r in rows):.0f} MHz big CPU mean {statistics.mean(r[5] for r in rows):.0f} MHz "
      f"| all reused={all(r[7] for r in rows)}", flush=True)
