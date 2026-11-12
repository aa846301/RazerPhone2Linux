#!/usr/bin/env python3
"""Read-only probe of the Music Assistant server API: auth requirement, players, music providers.
Usage: ma_probe.py http://HOST:8095"""
import json
import sys

import websocket

url = sys.argv[1].rstrip("/").replace("http://", "ws://") + "/ws"
ws = websocket.create_connection(url, timeout=10)
print("hello:", json.dumps(json.loads(ws.recv()))[:300])


def cmd(command, **args):
    mid = command
    ws.send(json.dumps({"message_id": mid, "command": command, "args": args}))
    while True:
        m = json.loads(ws.recv())
        if m.get("message_id") == mid:
            return m


r = cmd("players/all")
if "error_code" in r or "error" in r:
    print("players/all error:", json.dumps(r)[:300])
else:
    for p in r.get("result", []):
        print("player:", p.get("player_id"), p.get("display_name") or p.get("name"), p.get("provider"),
              p.get("state"), p.get("available"))
r = cmd("providers")
if "result" in r:
    for p in r["result"]:
        print("provider:", p.get("domain"), p.get("instance_id"), p.get("type"), p.get("available"))
else:
    print("providers error:", json.dumps(r)[:300])
