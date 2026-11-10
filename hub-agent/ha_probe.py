#!/usr/bin/env python3
"""Read-only check: connect to HA with ~/.config/razer-voice/ha.env and print the hub tiles and NLU registry."""
import json
import os
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ha import HA  # noqa: E402
import devices  # noqa: E402


def load_env(path):
    env = {}
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"')
    return env


env = load_env(os.path.expanduser("~/.config/razer-voice/ha.env"))
ready = threading.Event()
ha = HA(env["HA_URL"], env["HA_TOKEN"], lambda m: print(m, file=sys.stderr), lambda: ready.set())
t0 = time.time()
while time.time() - t0 < 15:
    if ha.snapshot()[4]:
        break
    time.sleep(0.2)
snap = ha.snapshot()
print("connected:", snap[4], "areas:", snap[1])
for t in devices.tiles(snap):
    print(f"  {t['glyph']} {t['name']:<12} {t['room']:<6} {t['kind']:<8} {t['sub']:<10} {t['id']}")
home = devices.nlu_home(snap)
print("NLU entities:", [(e["name"], e["domain"], e["aliases"]) for e in home["entities"]])
