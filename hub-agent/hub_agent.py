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
import subprocess
from datetime import datetime
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.expanduser("~/voice"))           # nlu.py, nlu_rules.py, nlu_slots.py

import devices  # noqa: E402
import music  # noqa: E402
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
        self.ha_url = env["HA_URL"].rstrip("/")
        self.ha = HA(env["HA_URL"], env["HA_TOKEN"], log, self._dirty.set)
        self._warm_req = threading.Event()
        self._warm_hash = None
        self.playlists = []                 # the user's own YouTube Music playlists (Music Assistant library)
        self.upnext = []                    # queue items after the current one
        self._upnext_key = None
        self._lib_req = threading.Event()
        threading.Thread(target=self._publisher, name="publish", daemon=True).start()
        threading.Thread(target=self._music_library_loop, name="music-lib", daemon=True).start()
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
                {"ev": "voice", "state": self.voice_state[0], "text": self.voice_state[1]}, self._music_state()]
        if conn is not None:                # lists change rarely: sent on connect and when they change
            msgs += [{"ev": "playlists", "items": self.playlists}, {"ev": "upnext", "items": self.upnext}]
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
        elif cmd == "music":                 # now-playing page buttons / volume slider
            op = {"op": m.get("op")}
            if m.get("op") in ("volume_set", "seek"):
                op["value"] = float(m.get("value", 0))
            if m.get("op") in ("play_playlist", "play_index"):
                op["index"] = int(m.get("value", -1))
            threading.Thread(target=self._music_ui, args=(op,), daemon=True).start()
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
        names = [e["name"] for e in home["entities"]]
        if prop.get("_conf") == "low":
            mi = music.parse(text, names)              # device rules unsure: is it about music?
            if mi:
                log(f"NLU[music] {text!r} -> {mi}")
                return {"via": "music", "music": mi, "proposal": {"actions": []}, "actions": [], "errors": [],
                        "confirm": False, "clarify": None, "reject": None}
        if prop.get("_conf") == "low":
            if self._slots_up():
                lp = self._llm_parser(home)
                prop, dt, tm = lp.parse(text)
                via = "llm"
                log(f"LLM {dt:.1f}s reused={tm.get('reused')} prompt_n={tm.get('prompt_n')} "
                    f"cache_n={tm.get('cache_n')} rewrite={prop.get('_rewrite')!r} slots={prop.get('_slots')}")
                mi = music.parse(prop.get("_rewrite") or "", names) if not prop.get("actions") else None
                if mi:                                 # e.g. 放點適合讀書的音樂 -> 「播放 讀書音樂」
                    log(f"NLU[llm-music] {text!r} -> {mi}")
                    return {"via": "llm-music", "music": mi, "proposal": {"actions": []}, "actions": [],
                            "errors": [], "confirm": False, "clarify": None, "reject": None}
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
        if plan.get("music"):
            return self._music(plan["music"])
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

    # ------------------------------------------------------------ music (Music Assistant via HA)
    def _ma_player(self):
        """The hub's own Music Assistant player entity (Sendspin client 「Razer 中控台」)."""
        want = os.environ.get("HUB_MA_PLAYER")
        states = self.ha.snapshot()[0]
        if want:
            return want if want in states else None
        for eid, st in states.items():
            if eid.startswith("media_player.") and st["attributes"].get("mass_player_type") and \
                    "razer" in eid:
                return eid
        return None

    def _music_candidates(self, resp, query):
        """Ordered playables for a search: an exact-ish song first; a singer's name plays the artist."""
        def norm(s):
            return re.sub(r"\s", "", (s or "")).lower()
        q = norm(query)
        tracks = resp.get("tracks") or []
        artists = resp.get("artists") or []
        exact_track = [t for t in tracks if norm(t.get("name")) == q or q in norm(t.get("name"))]
        artist_hit = [a for a in artists if norm(a.get("name")) == q]
        out = []
        if artist_hit and not exact_track:
            out += [("artist", a) for a in artist_hit]
        out += [("track", t) for t in exact_track]
        out += [("track", t) for t in tracks if t not in exact_track]
        out += [("artist", a) for a in artists if a not in artist_hit]
        out += [("album", a) for a in (resp.get("albums") or [])]
        out += [("playlist", p) for p in (resp.get("playlists") or [])]
        return out

    @staticmethod
    def _music_label(kind, item):
        artists = "、".join(a.get("name", "") for a in item.get("artists") or [])
        name = item.get("name", "")
        if kind == "artist":
            return f"{name} 的熱門歌曲"
        return f"{artists}－{name}" if artists else name

    def _music_play(self, player, idx):
        """Start playback in the background: Music Assistant needs ~5-7 s to resolve a YouTube stream, so the
        reply (title) goes out as soon as the search is done and the UI flips to the now-playing page."""
        kind, item = self.music_results[idx]
        self.music_idx = idx
        label = self._music_label(kind, item)
        artists = "、".join(a.get("name", "") for a in item.get("artists") or [])
        self.broadcast({"ev": "music_pending", "title": item.get("name", "") if kind != "artist" else label,
                        "artist": artists if kind != "artist" else ""})

        def start():
            try:
                data = {"media_id": item["uri"], "media_type": kind, "enqueue": "replace"}
                if kind == "track":
                    # Radio mode keeps the queue going with similar songs, so 下一首/上一首 work (a single
                    # track queue made 下一首 do nothing, user test 2026-11-11).
                    data["radio_mode"] = True
                self.ha.call_service("music_assistant", "play_media", player, data, timeout=30)
                log(f"music: playing {kind} {item.get('uri')} ({label})")
            except TimeoutError:
                log(f"music: play_media {item.get('uri')} sent, no confirmation yet")
            except Exception as e:
                log(f"music: play_media failed: {e!r}")
                self.set_voice("done", f"播放失敗：{e}")
        self._mute_during_switch(player, delay=1.0)    # after the reply chime
        threading.Thread(target=start, daemon=True).start()
        self.broadcast({"ev": "show", "page": "music"})
        return True, f"即將播放：{label}"

    def _music_state(self):
        """Now-playing info for the UI, from the hub player's HA entity; the cover is cached to a local file."""
        player = self._ma_player()
        st = self.ha.snapshot()[0].get(player) if player else None
        if not st:
            return {"ev": "music", "state": "off"}
        a = st.get("attributes", {})
        cover = ""
        url = a.get("entity_picture") or ""
        if url:
            if url.startswith("/"):
                url = self.ha_url + url
            if url != getattr(self, "_cover_url", None):
                self._cover_url, self._cover_path = url, ""
                threading.Thread(target=self._fetch_cover, args=(url,), daemon=True).start()
            cover = getattr(self, "_cover_path", "")
        upd = a.get("media_position_updated_at")
        try:
            upd_ts = datetime.fromisoformat(upd).timestamp() if upd else 0
        except ValueError:
            upd_ts = 0
        key = (a.get("media_title"), a.get("media_artist"), bool(a.get("shuffle")))
        if key != self._upnext_key:                     # new song or shuffle flipped: the queue order changed
            self._upnext_key = key
            threading.Thread(target=self._refresh_upnext, args=(player,), daemon=True).start()
        return {"ev": "music", "state": st.get("state"), "title": a.get("media_title") or "",
                "artist": a.get("media_artist") or "", "album": a.get("media_album_name") or "",
                "duration": a.get("media_duration") or 0, "position": a.get("media_position") or 0,
                "position_at": upd_ts, "volume": a.get("volume_level") or 0, "cover": cover,
                "shuffle": bool(a.get("shuffle"))}

    # ------------------------------------------------------------ music library: playlists, up next, sync
    @staticmethod
    def _img_url(img):
        """Image as returned by HA (URL string) or by MA directly (MediaItemImage dict)."""
        if isinstance(img, dict):
            img = img.get("path") if img.get("remotely_accessible", True) else ""
        return img if isinstance(img, str) and img.startswith("http") else ""

    def _cache_image(self, url, prefix):
        """Download an image into $XDG_RUNTIME_DIR/razer-hub/<prefix>-<hash>.jpg (once); returns the path or ''."""
        import hashlib
        if not url:
            return ""
        d = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "razer-hub")
        os.makedirs(d, exist_ok=True)
        base = os.path.join(d, f"{prefix}-" + hashlib.sha1(url.encode()).hexdigest()[:10])
        for ext in (".jpg", ".png", ".webp"):
            if os.path.exists(base + ext):
                return base + ext
        try:
            with urllib.request.urlopen(url, timeout=10) as r:
                data = r.read()
        except Exception as e:
            log(f"image download failed ({prefix}): {e!r}")
            return ""
        # the UI picks the decoder by file extension, so name the file after its real format
        ext = ".png" if data[:4] == b"\x89PNG" else ".webp" if data[8:12] == b"WEBP" else ".jpg"
        with open(base + ".tmp", "wb") as f:
            f.write(data)
        os.replace(base + ".tmp", base + ext)
        return base + ext

    @staticmethod
    def _prune_images(prefix, keep):
        d = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "razer-hub")
        for f in os.listdir(d) if os.path.isdir(d) else []:
            p = os.path.join(d, f)
            if f.startswith(prefix + "-") and p not in keep:
                os.remove(p)

    def _music_library_loop(self):
        """Load the playlist list once HA is up, then every 30 min or when asked (after a sync)."""
        while not self.ha.snapshot()[4]:
            time.sleep(1)
        while True:
            try:
                self._load_playlists()
            except Exception as e:
                log(f"playlists: load failed: {e!r}")
            self._lib_req.wait(timeout=1800)
            self._lib_req.clear()

    def _load_playlists(self):
        entry = self.ha.config_entry_id("music_assistant")
        r = self.ha.call_service("music_assistant", "get_library",
                                 data={"config_entry_id": entry, "media_type": "playlist", "limit": 100},
                                 timeout=30, return_response=True)
        items = ((r or {}).get("response") or {}).get("items") or []
        out = []
        for it in items:
            img = self._img_url(it.get("image"))
            # Music Assistant's own generated playlists ("500 Random tracks", "Infinite Mix", ...) all share
            # one picture served by MA's image proxy; the user's YouTube Music playlists have YouTube artwork.
            if not img or "/imageproxy/" in img:
                continue
            name = re.sub(r"\s*\(YouTube Music\)\s*$", "", it.get("name", ""))
            out.append({"name": name, "uri": it["uri"], "cover": self._cache_image(img, "pl")})
        # liked songs first, then by name
        out.sort(key=lambda p: ("喜歡" not in p["name"], p["name"].lower()))
        self._prune_images("pl", {p["cover"] for p in out})
        if out != self.playlists:
            self.playlists = out
            self.broadcast({"ev": "playlists", "items": out})
        log(f"playlists: {len(out)} ({', '.join(p['name'] for p in out)})")

    def _refresh_upnext(self, player):
        """Songs after the current one. Full list via Music Assistant's own API when a token is configured;
        otherwise HA's get_queue, which only knows the next item."""
        time.sleep(0.5)
        try:
            r = self.ha.call_service("music_assistant", "get_queue", player, timeout=5, return_response=True)
            q = ((r or {}).get("response") or {}).get(player) or {}
        except Exception as e:
            log(f"upnext: get_queue failed: {e!r}")
            return
        items, base = [], (q.get("current_index") or 0) + 1
        import ma_api
        if ma_api.available() and q.get("queue_id"):
            try:
                raw = ma_api.call("player_queues/items", queue_id=q["queue_id"], limit=10, offset=base) or []
                for i, it in enumerate(raw):
                    mi = it.get("media_item") or {}
                    items.append({"index": base + i, "title": mi.get("name") or it.get("name", ""),
                                  "artist": "、".join(a.get("name", "") for a in mi.get("artists") or []),
                                  "img": self._img_url(it.get("image") or mi.get("image"))})
            except Exception as e:
                log(f"upnext: MA queue items failed: {e!r}")
                items = []
        if not items and q.get("next_item"):
            it = q["next_item"]
            mi = it.get("media_item") or {}
            items = [{"index": -1, "title": mi.get("name") or it.get("name", ""),
                      "artist": "、".join(a.get("name", "") for a in mi.get("artists") or []),
                      "img": self._img_url(mi.get("image") or it.get("image")
                                           or (mi.get("album") or {}).get("image"))}]
        for it in items:
            it["cover"] = self._cache_image(it.pop("img"), "q")
        self._prune_images("q", {it["cover"] for it in items})
        self.upnext = items
        self.broadcast({"ev": "upnext", "items": items, "full": ma_api.available()})

    def _music_sync(self):
        import ma_api
        if not ma_api.available():
            self.broadcast({"ev": "sync", "state": "error", "text": "還沒設定 Music Assistant 的權杖"})
            return
        self.broadcast({"ev": "sync", "state": "running", "text": "同步中…"})
        try:
            ma_api.call("music/sync", timeout=20)
        except Exception as e:
            log(f"sync failed: {e!r}")
            self.broadcast({"ev": "sync", "state": "error", "text": f"同步失敗：{e}"})
            return
        log("sync: started")
        before = list(self.playlists)
        for wait in (15, 30, 60):                       # the sync runs in MA's background; reload a few times
            time.sleep(wait)
            try:
                self._load_playlists()
            except Exception as e:
                log(f"playlists: reload failed: {e!r}")
        changed = self.playlists != before
        self.broadcast({"ev": "sync", "state": "done",
                        "text": f"同步完成，{len(self.playlists)} 個播放清單" + ("" if changed else "（沒有變動）")})

    @staticmethod
    def _pl_norm(s):
        s = re.sub(r"\s|\(YouTube Music\)", "", s or "").lower()
        return re.sub(r"^(?:我的|我)|(?:播放清單|清單|歌單|列表)$", "", s)

    def _match_playlist(self, query):
        """A spoken 「播放我的 KTV 歌唱清單」 → that playlist. Needs a clear match so song names still search."""
        q = self._pl_norm(query)
        # 「我的…」/「…清單」 clearly mean the user's own list: a partial name is enough (「我喜歡」→ 喜歡的音樂)
        said_list = bool(re.search(r"清單|歌單|列表", query or "") or re.match(r"我", query or ""))
        if len(q) < 2:
            return None
        for i, p in enumerate(self.playlists):
            n = self._pl_norm(p["name"])
            if q == n or (n.startswith(q) and len(q) * 2 >= len(n)) or (said_list and (q in n or n in q)):
                return i
        return None

    def _play_playlist(self, player, i, shuffle=None):
        p = self.playlists[i]
        self.broadcast({"ev": "music_pending", "title": p["name"], "artist": "播放清單", "cover": p["cover"]})

        def start():
            try:
                if shuffle is not None:
                    self.ha.call_service("media_player", "shuffle_set", player, {"shuffle": shuffle})
                self.ha.call_service("music_assistant", "play_media", player,
                                     {"media_id": p["uri"], "media_type": "playlist", "enqueue": "replace"},
                                     timeout=30)
                log(f"music: playing playlist {p['uri']} ({p['name']})")
            except TimeoutError:
                log(f"music: play_media {p['uri']} sent, no confirmation yet")
            except Exception as e:
                log(f"music: playlist play failed: {e!r}")
                self.set_voice("done", f"播放失敗：{e}")
        self._mute_during_switch(player, delay=0.3)
        threading.Thread(target=start, daemon=True).start()
        self.broadcast({"ev": "show", "page": "music"})
        mode = {True: "隨機", False: "依序"}.get(shuffle, "")
        return True, f"{mode}播放清單：{p['name']}"

    def _fetch_cover(self, url):
        import hashlib
        d = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "razer-hub")
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, "cover-" + hashlib.sha1(url.encode()).hexdigest()[:10] + ".jpg")
        try:
            if not os.path.exists(path):
                with urllib.request.urlopen(url, timeout=10) as r, open(path + ".tmp", "wb") as f:
                    f.write(r.read())
                os.replace(path + ".tmp", path)
            for old in os.listdir(d):
                if old.startswith("cover-") and os.path.join(d, old) != path:
                    os.remove(os.path.join(d, old))
            if self._cover_url == url:
                self._cover_path = path
                self.broadcast(self._music_state())
        except Exception as e:
            log(f"cover download failed: {e!r}")

    @staticmethod
    def _music_stream_ids():
        """PipeWire ids of the sendspin playback stream(s) (the Music Assistant player), not the chimes."""
        try:
            nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout)
        except Exception:
            return []
        ids = []
        for n in nodes:
            p = (n.get("info") or {}).get("props") or {}
            if p.get("media.class") == "Stream/Output/Audio" and \
                    str(p.get("node.name", "")).startswith("alsa_playback.python"):
                ids.append(n["id"])
        return ids

    def _mute_during_switch(self, player, delay=0.0):
        """Optimistic UI shows the next title at once, but Music Assistant keeps playing the old song for seconds
        while it resolves the new YouTube stream (user: 「音源會滯後切換，怪怪的」). Mute the music stream until
        the player reports a different title (or 25 s pass)."""
        old = (self.ha.snapshot()[0].get(player) or {}).get("attributes", {}).get("media_title")

        def run():
            time.sleep(delay)                          # e.g. let the reply chime finish
            ids = self._music_stream_ids()
            for i in ids:
                subprocess.run(["wpctl", "set-mute", str(i), "1"], capture_output=True)
            t0 = time.time()
            while time.time() - t0 < 25:
                st = self.ha.snapshot()[0].get(player) or {}
                if st.get("attributes", {}).get("media_title") != old and st.get("state") == "playing":
                    break
                time.sleep(0.2)
            time.sleep(0.3)
            for i in set(ids) | set(self._music_stream_ids()):
                subprocess.run(["wpctl", "set-mute", str(i), "0"], capture_output=True)
        threading.Thread(target=run, daemon=True).start()

    def _announce_next(self, player):
        """Optimistic UI: tell the screen the queue's next title right away (Music Assistant takes seconds to
        switch streams). Best effort; the real state update follows."""
        try:
            r = self.ha.call_service("music_assistant", "get_queue", player, timeout=3, return_response=True)
            q = ((r or {}).get("response") or {}).get(player) or {}
            mi = (q.get("next_item") or {}).get("media_item") or {}
            if mi.get("name"):
                artists = "、".join(a.get("name", "") for a in mi.get("artists") or [])
                self.broadcast({"ev": "music_pending", "title": mi["name"], "artist": artists})
        except Exception as e:
            log(f"music: next-item lookup failed: {e!r}")

    def _music_ui(self, m):
        try:
            ok, msg = self._music(m)
            if not ok:
                self.set_voice("done", msg)
        except Exception as e:
            log(f"music UI command {m} failed: {e!r}")
            self.set_voice("done", f"音樂控制失敗：{e}")

    def _music(self, m):
        player = self._ma_player()
        if not player:
            return False, "找不到中控台的音樂播放器（Music Assistant 沒有連上）"
        op = m["op"]
        st = self.ha.snapshot()[0].get(player, {})
        if op == "play" and self._match_playlist(m["query"]) is not None:
            return self._play_playlist(player, self._match_playlist(m["query"]), m.get("shuffle"))
        if op == "play_playlist":
            if not 0 <= m.get("index", -1) < len(self.playlists):
                return False, "找不到這個播放清單"
            return self._play_playlist(player, m["index"])
        if op == "play_index":                          # tap on an "up next" item
            import ma_api
            r = self.ha.call_service("music_assistant", "get_queue", player, timeout=5, return_response=True)
            q = ((r or {}).get("response") or {}).get(player) or {}
            if m.get("index", -1) < 0 or not ma_api.available() or not q.get("queue_id"):
                return self._music({"op": "next"})
            hit = next((u for u in self.upnext if u["index"] == m["index"]), None)
            if hit:
                self.broadcast({"ev": "music_pending", "title": hit["title"], "artist": hit["artist"],
                                "cover": hit["cover"]})
            self._mute_during_switch(player)
            ma_api.call("player_queues/play_index", queue_id=q["queue_id"], index=m["index"])
            return True, ""
        if op in ("shuffle", "shuffle_on", "shuffle_off"):
            cur = bool(st.get("attributes", {}).get("shuffle"))
            want = {"shuffle": not cur, "shuffle_on": True, "shuffle_off": False}[op]
            self.ha.call_service("media_player", "shuffle_set", player, {"shuffle": want})
            return True, "隨機播放" if want else "依序播放"
        if op == "sync":
            threading.Thread(target=self._music_sync, daemon=True).start()
            return True, ""
        if op == "play":
            if m.get("shuffle") is not None:
                self.ha.call_service("media_player", "shuffle_set", player, {"shuffle": m["shuffle"]})
            entry = self.ha.config_entry_id("music_assistant")
            r = self.ha.call_service("music_assistant", "search",
                                     data={"config_entry_id": entry, "name": m["query"], "limit": 8},
                                     timeout=30, return_response=True)
            self.music_results = self._music_candidates((r or {}).get("response", {}), m["query"])
            if not self.music_results:
                return False, f"YouTube Music 找不到「{m['query']}」"
            return self._music_play(player, 0)
        if op == "another":
            results = getattr(self, "music_results", [])
            nxt = getattr(self, "music_idx", -1) + 1
            if nxt >= len(results):
                return False, "沒有其他搜尋結果了，請換個說法"
            return self._music_play(player, nxt)
        if op == "seek":
            self.ha.call_service("media_player", "media_seek", player, {"seek_position": round(m["value"], 1)})
            return True, ""
        if op == "next":
            # not for 上一首: it often restarts the same song, so the title never changes
            self._mute_during_switch(player)
            self._announce_next(player)
        simple = {"pause": "media_pause", "resume": "media_play", "stop": "media_stop",
                  "next": "media_next_track", "previous": "media_previous_track"}
        if op in simple:
            self.ha.call_service("media_player", simple[op], player)
            return True, {"pause": "已暫停", "resume": "繼續播放", "stop": "已停止播放",
                          "next": "下一首", "previous": "上一首"}[op]
        if op in ("volume_step", "volume_set"):
            cur = st.get("attributes", {}).get("volume_level") or 0.3
            vol = m["value"] if op == "volume_set" else cur + m["delta"]
            vol = round(min(1.0, max(0.0, vol)), 2)
            self.ha.call_service("media_player", "volume_set", player, {"volume_level": vol})
            return True, f"音樂音量 {round(vol * 100)}%"
        if op == "what":
            a = st.get("attributes", {})
            if st.get("state") not in ("playing", "paused") or not a.get("media_title"):
                return True, "現在沒有在播放音樂"
            who = a.get("media_artist")
            return True, f"現在播放：{who + '－' if who else ''}{a['media_title']}"
        return False, "不能理解，請重新再說一次"

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
