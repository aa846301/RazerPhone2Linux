#!/usr/bin/env python3
"""Razer hub agent: Home Assistant state + voice control, served to the hub UI over a Unix socket.

  HA (WebSocket, live states) ─┐
  DMIC → wake word → VAD → ASR ┼→ NLU (rules, then constrained-slot LLM if its server is up) → validate()
  UI socket (toggle / listen) ─┘                                                   → HA service calls

Socket: $XDG_RUNTIME_DIR/razer-hub.sock, newline-delimited JSON.
  UI -> agent: {"cmd":"toggle","id":E} {"cmd":"listen"} {"cmd":"cancel"} {"cmd":"hidden","ids":[...]}
  agent -> UI: {"ev":"devices","items":[...]} {"ev":"ha","connected":B} {"ev":"voice","state":S,"text":T}
Config: ~/.config/razer-voice/ha.env (HA_URL, HA_TOKEN). Env: HUB_NO_VOICE=1 disables the microphone,
HUB_SLOTS_URL (default http://127.0.0.1:8091) is the MNN OpenAI-style server for the slot LLM.
"""
import json
import os
import re
import socket
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.expanduser("~/voice"))           # nlu.py, nlu_rules.py, nlu_slots.py

import devices  # noqa: E402
from ha import HA  # noqa: E402


def log(msg):
    print(time.strftime("%F %T"), msg, flush=True)


def load_env(path):
    env = {}
    for line in open(path, encoding="utf-8"):
        line = line.strip().replace("\r", "")
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"')
    return env


VERB = {"turn_on": "打開", "turn_off": "關閉", "open": "打開", "close": "關上"}


class Agent:
    def __init__(self):
        env = load_env(os.path.expanduser("~/.config/razer-voice/ha.env"))
        self.clients = []
        self.clients_lock = threading.Lock()
        self.hidden = set()
        self.names = {}                     # entity_id -> hub-only display name (UI layout.json)
        self.dictate_id = None              # set while the next utterance renames this device
        self.voice_state = ("idle", "")
        self._dirty = threading.Event()
        self.slots_url = os.environ.get("HUB_SLOTS_URL", "http://127.0.0.1:8091")
        self.ha = HA(env["HA_URL"], env["HA_TOKEN"], log, self._dirty.set)
        threading.Thread(target=self._publisher, name="publish", daemon=True).start()
        self.voice = None
        if not os.environ.get("HUB_NO_VOICE"):
            try:
                from voice import Voice
                self.voice = Voice(log, self.set_voice, self.handle_text)
            except Exception as e:
                log(f"voice disabled: {e!r}")

    # ------------------------------------------------------------ UI protocol
    def broadcast(self, obj):
        data = (json.dumps(obj, ensure_ascii=False) + "\n").encode()
        with self.clients_lock:
            for c in list(self.clients):
                try:
                    c.sendall(data)
                except OSError:
                    self.clients.remove(c)

    def _publisher(self):
        """Coalesce HA change bursts (state_changed storms) into one UI update every 150 ms at most."""
        while True:
            self._dirty.wait()
            time.sleep(0.15)
            self._dirty.clear()
            self._send_state()

    def _send_state(self, conn=None):
        snap = self.ha.snapshot()
        msgs = [{"ev": "ha", "connected": snap[4]}, {"ev": "devices", "items": devices.tiles(snap, self.names)},
                {"ev": "voice", "state": self.voice_state[0], "text": self.voice_state[1]}]
        for m in msgs:
            if conn is None:
                self.broadcast(m)
            else:
                conn.sendall((json.dumps(m, ensure_ascii=False) + "\n").encode())

    def set_voice(self, state, text):
        if self.dictate_id and state == "listening":
            text = "請說新的名稱…"
        elif state in ("idle", "done"):
            self.dictate_id = None          # cancelled, nothing heard, or finished
        self.voice_state = (state, text)
        self.broadcast({"ev": "voice", "state": state, "text": text})

    def serve(self):
        path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "razer-hub.sock")
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(path)
        os.chmod(path, 0o600)
        srv.listen(4)
        log(f"listening on {path}")
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=self._client, args=(conn,), daemon=True).start()

    def _client(self, conn):
        with self.clients_lock:
            self.clients.append(conn)
        try:
            self._send_state(conn)
            buf = b""
            while True:
                data = conn.recv(4096)
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip():
                        self._command(json.loads(line))
        except (OSError, ValueError) as e:
            log(f"client error: {e!r}")
        finally:
            with self.clients_lock:
                if conn in self.clients:
                    self.clients.remove(conn)
            conn.close()

    def _command(self, m):
        cmd = m.get("cmd")
        if cmd == "toggle":
            threading.Thread(target=self.toggle, args=(m.get("id"),), daemon=True).start()
        elif cmd == "listen":
            if self.voice:
                self.voice.listen()
            else:
                self.set_voice("done", "麥克風未啟用")
        elif cmd == "cancel" and self.voice:
            self.voice.cancel()
        elif cmd == "hidden":
            self.hidden = set(m.get("ids") or [])
        elif cmd == "names":
            self.names = {k: v for k, v in (m.get("map") or {}).items() if v}
            self._dirty.set()
        elif cmd == "dictate":               # next utterance renames device m["id"]
            if self.voice and not self.voice.busy:
                self.dictate_id = m.get("id")
                self.voice.listen()
        elif cmd == "text":                  # testing: run a typed sentence through NLU (dry_run: no HA calls)
            if m.get("dry_run"):
                self.broadcast({"ev": "dry_run", "text": m.get("text"), "result": self._plan(m.get("text", ""))})
            else:
                threading.Thread(target=self.handle_text, args=(m.get("text", ""),), daemon=True).start()

    # ------------------------------------------------------------ actions
    def toggle(self, eid):
        st = self.ha.snapshot()[0].get(eid)
        if not st:
            return
        domain, service = devices.toggle_service(eid, st.get("state"))
        try:
            self.ha.call_service(domain, service, eid, timeout=devices.service_timeout(domain))
            log(f"toggle {eid}: {domain}.{service}")
        except TimeoutError:
            # HA runs the call anyway; slow devices (BLE curtain robots) just confirm late.
            log(f"toggle {eid}: {domain}.{service} sent, no confirmation yet")
            self.set_voice("done", "指令已送出，但裝置沒有回報結果")
        except Exception as e:
            log(f"toggle {eid} failed: {e}")
            self.set_voice("done", f"操作失敗：{e}")

    def handle_text(self, text):
        """Utterance -> NLU -> validated HA calls -> reply text + chime (or a rename, when dictating)."""
        if self.dictate_id:
            eid, self.dictate_id = self.dictate_id, None
            name = re.sub(r"[\s。，、！？!?,.「」]", "", text)[:12]
            if not name:
                self._reply(False, "沒有聽清楚名稱，改名取消")
                return
            log(f"rename {eid} -> {name!r}")
            self.broadcast({"ev": "rename", "id": eid, "name": name})
            self._reply(True, f"已改名為「{name}」")
            return
        if not text:
            self._reply(False, "沒有聽清楚，請再說一次")
            return
        self.set_voice("thinking", f"「{text}」")
        try:
            if os.environ.get("HUB_DRY_RUN"):          # voice testing: show the plan, do not touch devices
                p = self._plan(text)
                acts = "、".join(self._describe(a[0], a[1], a[2] if len(a) > 2 else None) for a in p["actions"])
                ok, reply = True, "（測試，不執行）" + (acts or p.get("clarify") or p.get("reject") or "沒有動作")
            else:
                ok, reply = self._execute(text)
        except Exception as e:
            log(f"command failed: {e!r}")
            ok, reply = False, f"執行失敗：{e}"
        self._reply(ok, f"「{text}」\n{reply}")

    def _reply(self, ok, text):
        if self.voice:
            self.voice.play("ok" if ok else "fail")
        self.set_voice("done", text)

        def back_to_idle(snapshot=text):
            time.sleep(6)
            if self.voice_state == ("done", snapshot):
                self.set_voice("idle", "")
        threading.Thread(target=back_to_idle, daemon=True).start()

    def _slots_up(self):
        try:
            urllib.request.urlopen(self.slots_url + "/health", timeout=0.3)
            return True
        except Exception:
            return False

    def _plan(self, text):
        """NLU only: (home, proposal, validated result, parser used)."""
        from nlu import validate
        from nlu_rules import RuleParser
        home = devices.nlu_home(self.ha.snapshot(), self.hidden, self.names)
        prop = RuleParser(home).parse(text)
        via = "rules"
        if prop.get("_conf") == "low" and self._slots_up():
            from nlu_slots import SlotParser
            prop, _, _ = SlotParser(home, self.slots_url, compact=True).parse(text)
            via = "slots"
        res = validate(home, prop)
        log(f"NLU[{via}] {text!r} -> {res}" + (f" slots={prop.get('_slots')}" if via == "slots" else ""))
        return {"via": via, "proposal": {k: v for k, v in prop.items() if not k.startswith("_")}, **res}

    def _execute(self, text):
        snap = self.ha.snapshot()
        if not snap[4]:
            return False, "HA 未連線"
        home = devices.nlu_home(snap, self.hidden, self.names)
        plan = self._plan(text)
        prop, res = plan["proposal"], plan
        if res.get("confirm"):
            return False, "這個操作需要確認，請在畫面上操作"
        if not res["actions"]:
            if res.get("clarify"):
                return False, res["clarify"]
            if res.get("reject"):
                return False, res["reject"]
            if res.get("errors"):
                return False, "做不到：" + "；".join(res["errors"][:2])
            if prop.get("actions"):
                return True, "設備已經是這個狀態了"
            return False, "我不太懂這句話，可以換個說法嗎？"
        ents = {e["entity_id"]: e for e in home["entities"]}
        done = []
        for a in res["actions"]:
            eid, op = a[0], a[1]
            val = a[2] if len(a) > 2 else None
            e = ents[eid]
            domain, service, data = devices.service_for(e["ha_domain"], op, val)
            try:
                self.ha.call_service(domain, service, eid, data, timeout=devices.service_timeout(domain))
                done.append(self._describe(e["name"], op, val))
            except TimeoutError:
                log(f"{domain}.{service} {eid}: sent, no confirmation yet")
                done.append(self._describe(e["name"], op, val) + "（裝置沒有回報結果）")
        return True, "已" + "、".join(done)

    @staticmethod
    def _describe(name, op, val):
        if op in VERB:
            return VERB[op] + name
        if op == "set_brightness":
            return f"把{name}亮度調到 {val:g}%"
        if op == "set_temperature":
            return f"把{name}設定為 {val:g} 度"
        if op == "set_percentage":
            return f"把{name}調到 {val:g}%"
        if op == "set_position":
            return f"把{name}開到 {val:g}%"
        return f"{op} {name}"


if __name__ == "__main__":
    Agent().serve()
