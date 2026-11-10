"""Home Assistant WebSocket client for the Razer hub agent.

One background thread keeps a WebSocket open (auto-reconnect with backoff), loads the area/device/entity
registries plus all states, and follows `state_changed` events. Callers get a consistent snapshot through
`snapshot()` and issue service calls with `call_service()` (blocking, with timeout).
"""
import itertools
import json
import threading
import time

import websocket  # websocket-client


class HA:
    def __init__(self, url, token, log, on_change):
        self.ws_url = url.rstrip("/").replace("http://", "ws://").replace("https://", "wss://") + "/api/websocket"
        self.token = token
        self.log = log
        self.on_change = on_change          # called (from the HA thread) after states/registries change
        self.lock = threading.Lock()
        self.states = {}                    # entity_id -> state object
        self.areas = {}                     # area_id -> name
        self.entities = {}                  # entity_id -> entity registry entry
        self.devices = {}                   # device_id -> device registry entry
        self.connected = False
        self._ids = itertools.count(1)
        self._pending = {}                  # id -> [Event, result]
        self._ws = None
        threading.Thread(target=self._run, name="ha", daemon=True).start()

    # ------------------------------------------------------------------ public
    def snapshot(self):
        with self.lock:
            return dict(self.states), dict(self.areas), dict(self.entities), dict(self.devices), self.connected

    def call_service(self, domain, service, entity_id, data=None, timeout=8):
        msg = {"type": "call_service", "domain": domain, "service": service,
               "target": {"entity_id": entity_id}, "service_data": data or {}}
        return self._request(msg, timeout)

    # ----------------------------------------------------------------- private
    def _request(self, msg, timeout):
        ws = self._ws
        if ws is None or not self.connected:
            raise RuntimeError("HA 未連線")
        i = next(self._ids)
        ev = threading.Event()
        self._pending[i] = [ev, None]
        ws.send(json.dumps({**msg, "id": i}))
        if not ev.wait(timeout):
            self._pending.pop(i, None)
            raise TimeoutError(f"HA 無回應：{msg.get('type')}")
        res = self._pending.pop(i)[1]
        if not res.get("success", False):
            raise RuntimeError(res.get("error", {}).get("message", "HA 回報失敗"))
        return res.get("result")

    def _set_connected(self, v):
        with self.lock:
            changed = self.connected != v
            self.connected = v
        if changed:
            self.on_change()

    def _run(self):
        backoff = 2
        while True:
            try:
                self._session()
                backoff = 2
            except Exception as e:  # network errors, auth failures, HA restarts
                self.log(f"HA connection error: {e!r}")
            self._ws = None
            self._set_connected(False)
            for ev, _ in list(self._pending.values()):
                ev.set()
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)

    def _session(self):
        ws = websocket.create_connection(self.ws_url, timeout=15)
        try:
            hello = json.loads(ws.recv())
            if hello.get("type") != "auth_required":
                raise RuntimeError(f"unexpected hello {hello.get('type')}")
            ws.send(json.dumps({"type": "auth", "access_token": self.token}))
            auth = json.loads(ws.recv())
            if auth.get("type") != "auth_ok":
                raise RuntimeError("HA 驗證失敗（token 無效？）")
            self.log(f"HA connected, version {auth.get('ha_version')}")
            ws.settimeout(None)
            self._ws = ws
            self._ids = itertools.count(1)
            # Load registries/states synchronously on this thread before dispatching events.
            want = {}
            for t in ("config/area_registry/list", "config/device_registry/list",
                      "config/entity_registry/list", "get_states", "subscribe_events"):
                i = next(self._ids)
                msg = {"type": t, "id": i}
                if t == "subscribe_events":
                    msg["event_type"] = "state_changed"
                ws.send(json.dumps(msg))
                want[i] = t
            got = {}
            while len(got) < len(want):
                m = json.loads(ws.recv())
                if m.get("type") == "result" and m.get("id") in want:
                    if not m.get("success"):
                        raise RuntimeError(f"{want[m['id']]} failed: {m.get('error')}")
                    got[want[m["id"]]] = m.get("result")
            with self.lock:
                self.areas = {a["area_id"]: a["name"] for a in got["config/area_registry/list"]}
                self.devices = {d["id"]: d for d in got["config/device_registry/list"]}
                self.entities = {e["entity_id"]: e for e in got["config/entity_registry/list"]}
                self.states = {s["entity_id"]: s for s in got["get_states"]}
            self._set_connected(True)
            self.on_change()
            while True:
                raw = ws.recv()
                if not raw:
                    raise ConnectionError("HA closed the connection")
                m = json.loads(raw)
                if m.get("type") == "event":
                    d = m["event"]["data"]
                    with self.lock:
                        if d.get("new_state") is None:
                            self.states.pop(d["entity_id"], None)
                        else:
                            self.states[d["entity_id"]] = d["new_state"]
                    self.on_change()
                elif m.get("type") == "result" and m.get("id") in self._pending:
                    p = self._pending[m["id"]]
                    p[1] = m
                    p[0].set()
        finally:
            try:
                ws.close()
            except Exception:
                pass
