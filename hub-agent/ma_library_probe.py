#!/usr/bin/env python3
"""Read-only: list the Music Assistant library playlists through HA (music_assistant.get_library)."""
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
for kind in ("playlist", "album", "artist"):
    t = time.time()
    r = ha.call_service("music_assistant", "get_library",
                        data={"config_entry_id": entry, "media_type": kind, "limit": 50},
                        timeout=30, return_response=True)
    items = ((r or {}).get("response") or {}).get("items") or []
    print(f"== {kind}: {len(items)} items in {time.time() - t:.1f}s")
    for it in items[:15]:
        print(f"  {it.get('name')} | {it.get('uri')} | image={'yes' if it.get('image') else 'no'}"
              f" | owner={it.get('owner', '')}")
    if items and os.environ.get("RAW"):
        print(json.dumps(items[0], ensure_ascii=False)[:800])
