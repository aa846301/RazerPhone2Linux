#!/usr/bin/env python3
"""Read-only: search YouTube Music through HA's Music Assistant integration and print the top results.
Usage: ma_search_probe.py "七里香" """
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ha import HA  # noqa: E402
from hub_agent import load_env  # noqa: E402

env = load_env(os.path.expanduser("~/.config/razer-voice/ha.env"))
ha = HA(env["HA_URL"], env["HA_TOKEN"], lambda m: None, lambda: None)
t0 = time.time()
while not ha.snapshot()[4] and time.time() - t0 < 15:
    time.sleep(0.2)
entry = ha.config_entry_id("music_assistant")
print("config entry:", entry)
for q in sys.argv[1:]:
    t = time.time()
    r = ha.call_service("music_assistant", "search", data={"config_entry_id": entry, "name": q, "limit": 5},
                        timeout=30, return_response=True)
    resp = (r or {}).get("response", {})
    print(f"== {q}: {time.time() - t:.1f}s keys={list(resp)}")
    for kind in ("tracks", "artists", "albums", "playlists"):
        for it in (resp.get(kind) or [])[:3]:
            artists = "、".join(a.get("name", "") for a in it.get("artists") or [])
            print(f"  {kind[:-1]:<8} {it.get('name')} | {artists} | {it.get('uri')}")
    if "--raw" in os.environ.get("PROBE_FLAGS", ""):
        print(json.dumps(resp, ensure_ascii=False)[:1500])
