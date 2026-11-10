#!/usr/bin/env python3
"""Talk to the running hub agent from a shell.
  agent_cli.py events                 print events for 10 s
  agent_cli.py parse "把主臥燈關掉"     NLU dry run (no HA calls)
  agent_cli.py listen                 same as pressing the mic button
"""
import json
import os
import socket
import sys
import time

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "razer-hub.sock"))
cmd = sys.argv[1] if len(sys.argv) > 1 else "events"
if cmd == "parse":
    for t in sys.argv[2:]:
        s.sendall((json.dumps({"cmd": "text", "text": t, "dry_run": True}, ensure_ascii=False) + "\n").encode())
elif cmd == "listen":
    s.sendall(b'{"cmd":"listen"}\n')
s.settimeout(0.5)
buf, end = b"", time.time() + (10 if cmd != "parse" else 5 + 10 * len(sys.argv[2:]))
while time.time() < end:
    try:
        d = s.recv(65536)
    except socket.timeout:
        continue
    if not d:
        break
    buf += d
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        m = json.loads(line)
        if m.get("ev") == "devices":
            print("devices:", len(m["items"]), "items")
        elif cmd != "parse" or m.get("ev") == "dry_run":
            print(json.dumps(m, ensure_ascii=False))
