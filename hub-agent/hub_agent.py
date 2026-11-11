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
        self._warm_req = threading.Event()
        self._warm_hash = None
        threading.Thread(target=self._publisher, name="publish", daemon=True).start()
        threading.Thread(target=self._llm_warmer, name="llm-warm", daemon=True).start()
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
            self._warm_req.set()

    def _llm_warmer(self):
        """Keep the LLM server's prefix cache on *our* system prompt. The MNN worker caches one prefix; a miss
        re-reads ~820 tokens and costs ~35-40 s (measured 2026-11-11), a hit ~2.6 s. The prompt depends only on
        device names/rooms (not on states), so it changes rarely: at start, on hide/rename, or after something
        else (an eval run) used the server. Re-prime it in the background whenever it changed."""
        time.sleep(10)        # let the UI reconnect and send hidden/names first, or the first warm-up is wasted
        server_started = None
        while True:
            self._warm_req.wait(timeout=30)
            # A restarted LLM server has an empty prefix cache: re-prime even if our prompt did not change.
            try:
                with urllib.request.urlopen(self.slots_url + "/health", timeout=1) as r:
                    started = json.load(r).get("started")
                if started != server_started:
                    server_started, self._warm_hash = started, None
                    self._warm_req.set()
            except Exception:
                pass
            if not self._warm_req.is_set():
                continue
            time.sleep(2)                      # debounce bursts of HA events
            self._warm_req.clear()
            snap = self.ha.snapshot()
            if not snap[4]:
                continue
            sp = self._llm_parser(devices.nlu_home(snap, self.hidden, self.names))
            h = hash(sp.system)
            if h == self._warm_hash:
                continue
            if not self._slots_up():
                self._warm_req.set()
                time.sleep(15)                 # server still loading: retry
                continue
            t0 = time.time()
            try:
                sp.ask("你好")
                self._warm_hash = h
                log(f"LLM prompt cache primed in {time.time() - t0:.1f}s (system_hash={h & 0xffff:04x})")
            except Exception as e:
                log(f"LLM warm-up failed: {e!r}")

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
            self._warm_req.set()
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

    def _llm_parser(self, home):
        """LLM fallback: 'rewrite' (default; paraphrase to a canonical command that the rules execute) or the
        older constrained-slot JSON parser ('slots'), via HUB_NLU_LLM."""
        if os.environ.get("HUB_NLU_LLM", "rewrite") == "slots":
            from nlu_slots import SlotParser
            return SlotParser(home, self.slots_url, compact=True)
        from nlu_rewrite import RewriteParser
        return RewriteParser(home, self.slots_url)

    def _plan(self, text):
        """Flow (user's design, 2026-11-11): rules first; only if they are unsure, the LLM rewrites the sentence
        into a canonical command and the rules parse that; anything still unclear -> "不能理解，請重新再說一次"."""
        from nlu import validate
        from nlu_rules import RuleParser
        from nlu_rewrite import RewriteParser
        snap = self.ha.snapshot()
        home = devices.nlu_home(snap, self.hidden, self.names)
        hidden_hit = self._hidden_mention(snap, home, text)
        if hidden_hit:
            msg = f"「{hidden_hit}」已在中控台隱藏，不能用語音控制"
            log(f"NLU[hidden] {text!r} -> {msg}")
            return {"via": "hidden", "proposal": {"actions": [], "reject": msg}, "actions": [], "errors": [],
                    "confirm": False, "clarify": None, "reject": msg}
        prop = RuleParser(home).parse(text)
        via = "rules"
        if prop.get("_conf") == "low":
            if self._slots_up():
                lp = self._llm_parser(home)
                prop, dt, tm = lp.parse(text)
                via = "llm"
                log(f"LLM {dt:.1f}s reused={tm.get('reused')} prompt_n={tm.get('prompt_n')} "
                    f"cache_n={tm.get('cache_n')} rewrite={prop.get('_rewrite')!r} slots={prop.get('_slots')}")
            else:
                prop = {"actions": [], "clarify": RewriteParser.NOT_UNDERSTOOD}
                via = "rules (LLM offline)"
        res = validate(home, prop)
        log(f"NLU[{via}] {text!r} -> {res}")
        return {"via": via, "proposal": {k: v for k, v in prop.items() if not k.startswith("_")}, **res}

    def _hidden_mention(self, snap, home, text):
        """Name of a hidden device mentioned in text, unless that name also belongs to a visible device
        (e.g. the user renamed one AC to 冷氣 and hid the others called 冷氣: 冷氣 must still work)."""
        if not self.hidden:
            return None
        def terms(entities):
            return {t for e in entities for t in [e["name"], *e.get("aliases", [])] if t}
        visible = terms(home["entities"])
        everything = devices.nlu_home(snap, (), self.names)
        hidden = terms(e for e in everything["entities"] if e["entity_id"] in self.hidden) - visible
        hits = [t for t in hidden if t in text]
        return max(hits, key=len) if hits else None

    @staticmethod
    def _explain(errors, ents):
        """validate() error strings -> reasons the user can act on."""
        def name(eid):
            return ents.get(eid, {}).get("name", eid)
        out = []
        for e in errors:
            m = re.match(r"(unknown entity|entity not allowed) (\S+)", e)
            if m:
                out.append(f"{name(m.group(2))}目前離線或不能控制" if m.group(1) == "entity not allowed"
                           else "找不到這個裝置")
                continue
            m = re.match(r"op (\S+) unsupported for (\S+)", e)
            if m:
                out.append(f"{name(m.group(2))}不支援這個操作")
                continue
            m = re.match(r"temperature (\S+) out of range (\S+)-(\S+)", e)
            if m:
                out.append(f"溫度要在 {float(m.group(2)):g}–{float(m.group(3)):g} 度之間")
                continue
            m = re.match(r"missing value for (\S+)", e)
            if m:
                out.append(f"{name(m.group(1))}要設成多少呢？")
                continue
            if "out of range" in e:
                out.append("數值要在 0–100 之間")
                continue
            out.append(e)
        return "；".join(dict.fromkeys(out))

    def _execute(self, text):
        snap = self.ha.snapshot()
        if not snap[4]:
            return False, "HA 未連線"
        from nlu_rewrite import RewriteParser
        home = devices.nlu_home(snap, self.hidden, self.names)
        ents = {e["entity_id"]: e for e in home["entities"]}
        plan = self._plan(text)
        prop, res = plan["proposal"], plan
        if res.get("confirm"):
            return False, "這個操作需要確認，請在畫面上操作"
        if not res["actions"]:
            if res.get("errors"):                       # validation: say why (offline, out of range, ...)
                return False, "做不到：" + self._explain(res["errors"], ents)
            if res.get("clarify"):                      # ambiguity ("哪一台冷氣？") or not understood
                return False, res["clarify"]
            if res.get("reject"):
                return False, res["reject"]
            if prop.get("actions"):
                return True, "設備已經是這個狀態了"
            return False, RewriteParser.NOT_UNDERSTOOD
        done, failed = [], []
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
            except Exception as ex:                     # HA error: show it as-is (user's request)
                log(f"HA error {domain}.{service} {eid} {data}: {ex!r}")
                failed.append(f"{e['name']}：HA 回報 {domain}.{service} 失敗：{ex}")
        msg = ("已" + "、".join(done)) if done else ""
        if failed:
            return False, (msg + "\n" if msg else "") + "\n".join(failed)
        return True, msg

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
