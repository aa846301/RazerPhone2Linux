#!/usr/bin/env python3
"""Time the slot-LLM on the live HA registry: prompt size, prefill/decode split, raw output.
Usage: llm_probe.py "句子" [...]"""
import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(1, os.path.expanduser("~/voice"))
import devices  # noqa: E402
from ha import HA  # noqa: E402
from hub_agent import load_env  # noqa: E402
from nlu_slots import SlotParser  # noqa: E402

env = load_env(os.path.expanduser("~/.config/razer-voice/ha.env"))
ready = threading.Event()
ha = HA(env["HA_URL"], env["HA_TOKEN"], lambda m: None, ready.set)
t0 = time.time()
while not ha.snapshot()[4] and time.time() - t0 < 15:
    time.sleep(0.2)
home = devices.nlu_home(ha.snapshot())
sp = SlotParser(home, os.environ.get("PROBE_URL", "http://127.0.0.1:8091"), compact=True)
print("system prompt chars:", len(sp.system), "| devices:", len(sp.devices), "| rooms:", len(sp.rooms))
for text in sys.argv[1:]:
    t = time.time()
    slots, tm = sp.ask(text)
    print(f"{text}: {time.time() - t:.1f}s timings={tm} -> {slots}")
