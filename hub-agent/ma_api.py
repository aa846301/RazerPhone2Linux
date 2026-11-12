"""Minimal Music Assistant WebSocket API client (direct, not through HA).

HA's music_assistant integration has no "sync library" service and its get_queue only returns the current and
the next item, so the hub talks to MA itself for those two things. Needs a long-lived token created by the user
in MA (Profile -> Long-lived access tokens), stored in ~/.config/razer-hub/ma.env:
    MA_URL=http://192.168.10.185:8095
    MA_TOKEN=...
Protocol (music-assistant/server webserver/websocket_client.py): the server sends its server-info message first;
the client sends {"message_id", "command": "auth", "args": {"token"}}; then commands
{"message_id", "command", "args"} -> {"message_id", "result", "partial"?} or {"message_id", "error_code", "details"}.
One short-lived connection per call keeps this simple; calls are rare (button presses, title changes).
"""
import itertools
import json
import os

import websocket  # websocket-client

_ids = itertools.count(1)


def _load():
    path = os.path.expanduser("~/.config/razer-hub/ma.env")
    env = {}
    try:
        for line in open(path, encoding="utf-8"):
            line = line.strip().replace("\r", "")
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"')
    except FileNotFoundError:
        pass
    return env.get("MA_URL", "").rstrip("/"), env.get("MA_TOKEN", "")


def available():
    url, token = _load()
    return bool(url and token)


class MAError(Exception):
    pass


def call(command, timeout=15, **args):
    url, token = _load()
    if not (url and token):
        raise MAError("no MA token (~/.config/razer-hub/ma.env)")
    ws = websocket.create_connection(url.replace("http", "ws", 1) + "/ws", timeout=timeout)
    try:
        json.loads(ws.recv())                                   # server info
        ws.send(json.dumps({"message_id": str(next(_ids)), "command": "auth", "args": {"token": token}}))
        r = json.loads(ws.recv())
        if "error_code" in r or not (r.get("result") or {}).get("authenticated"):
            raise MAError(f"auth failed: {r.get('details') or r.get('error_code')}")
        mid = str(next(_ids))
        ws.send(json.dumps({"message_id": mid, "command": command, "args": args}))
        out = None
        while True:
            r = json.loads(ws.recv())
            if r.get("message_id") != mid:
                continue                                        # events
            if "error_code" in r:
                raise MAError(f"{command}: {r.get('details') or r.get('error_code')}")
            res = r.get("result")
            if r.get("partial"):
                out = (out or []) + list(res or [])
                continue
            if out is not None:
                return out + list(res or [])
            return res
    finally:
        ws.close()
