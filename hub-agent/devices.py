"""Turn a Home Assistant snapshot into (a) tiles for the hub UI and (b) the `home` registry the NLU expects.

Shown on the hub: light, switch, fan, climate, cover entities that are not disabled/hidden in HA and are not
configuration/diagnostic entities (e.g. a smart plug's 兒童鎖 switch). The user can hide more from the hub UI.
"""
import re

CONTROL_DOMAINS = ("light", "switch", "fan", "climate", "cover")
ON_STATES = {"on", "open", "opening", "heat", "cool", "heat_cool", "auto", "dry", "fan_only"}
# Everyday words for HA area names (HA areas carry no aliases here). "房間好暗" must reach 臥室.
AREA_ALIASES = {
    "臥室": ("房間", "臥房", "主臥", "睡房", "寢室"),
    "客廳": ("大廳",),
    "廚房": ("灶腳",),
    "廁所": ("浴室", "洗手間"),
    "陽台": ("陽臺",),
}
NOISE = re.compile(r"兒童鎖|child[ _]?lock|指示燈|indicator|backlight", re.I)


def _area(eid, ent, devices):
    if ent:
        if ent.get("area_id"):
            return ent["area_id"]
        dev = devices.get(ent.get("device_id") or "")
        if dev and dev.get("area_id"):
            return dev["area_id"]
    return None


def _glyph(domain, name):
    if domain == "light" or "燈" in name:
        return "燈"
    return {"fan": "扇", "climate": "冷", "cover": "簾"}.get(domain) or ("扇" if "扇" in name else "插")


def _kind(domain, name):
    if domain == "switch" and "燈" in name:
        return "light"
    return domain


def controllable(snapshot):
    """[(entity_id, state, entity_registry_entry, area_id)] for hub-worthy entities, stable order."""
    states, areas, entities, devices, _ = snapshot
    out = []
    for eid in sorted(states):
        domain = eid.split(".", 1)[0]
        if domain not in CONTROL_DOMAINS:
            continue
        ent = entities.get(eid)
        if ent and (ent.get("disabled_by") or ent.get("hidden_by") or ent.get("entity_category")):
            continue
        st = states[eid]
        name = st.get("attributes", {}).get("friendly_name") or eid
        if NOISE.search(name) or NOISE.search(eid):
            continue
        out.append((eid, st, ent, _area(eid, ent, devices)))
    return out


def tiles(snapshot, names=None):
    """names: hub-only display names {entity_id: name} chosen by the user (they override friendly_name)."""
    _, areas, _, _, _ = snapshot
    names = names or {}
    items = []
    for eid, st, ent, area in controllable(snapshot):
        domain = eid.split(".", 1)[0]
        name = names.get(eid) or st.get("attributes", {}).get("friendly_name") or eid
        s = st.get("state", "unknown")
        available = s not in ("unavailable", "unknown")
        if domain == "climate" and available:
            t = st["attributes"].get("temperature")
            sub = ("關閉" if s == "off" else f"{_mode_zh(s)} {t:g}°" if isinstance(t, (int, float)) else _mode_zh(s))
        elif domain == "cover" and available:
            sub = {"open": "開啟", "closed": "關閉", "opening": "開啟中", "closing": "關閉中"}.get(s, s)
            pos = st["attributes"].get("current_position")
            if isinstance(pos, (int, float)) and s == "open" and pos < 100:
                sub = f"開啟 {pos:g}%"     # HA calls any position > 0 "open"; show how open it really is
        elif domain == "light" and available and s == "on" and st["attributes"].get("brightness"):
            sub = f"開啟 {round(st['attributes']['brightness'] / 2.55)}%"
        else:
            sub = ("開啟" if s in ON_STATES else "關閉") if available else "離線"
        items.append({"id": eid, "name": name, "room": areas.get(area, "") if area else "",
                      "kind": _kind(domain, name), "on": s in ON_STATES, "available": available,
                      "glyph": _glyph(domain, name), "sub": sub})
    return items


def _mode_zh(m):
    return {"cool": "冷氣", "heat": "暖氣", "heat_cool": "自動", "auto": "自動", "dry": "除濕",
            "fan_only": "送風", "off": "關閉"}.get(m, m)


def nlu_home(snapshot, hidden=(), names=None):
    """Registry in the format of experiments/voice-hub/home.json, built from live HA data. A hub-only name
    (names[entity_id]) becomes the device name; the HA friendly_name stays as an alias."""
    states, areas, _, _, _ = snapshot
    names = names or {}
    home = {"areas": {}, "entities": [], "state": {}}
    for aid, aname in areas.items():
        home["areas"][aid] = [aname] + [a for a in AREA_ALIASES.get(aname, ()) if a not in areas.values()]
    for eid, st, ent, area in controllable(snapshot):
        if eid in hidden:
            continue                       # hidden on the hub: never a voice target
        # Offline devices stay in the registry (so the LLM prompt, and its prefix cache, do not change every time
        # a plug drops off Wi-Fi) but are not allowed: validate() rejects them.
        online = st.get("state") not in ("unavailable", "unknown")
        domain = eid.split(".", 1)[0]
        attrs = st.get("attributes", {})
        ha_name = attrs.get("friendly_name") or eid
        name = names.get(eid) or ha_name
        aliases = list((ent or {}).get("aliases") or [])
        if name != ha_name:
            aliases.append(ha_name)
        # Smart-plug entities are named like "檯燈 插座 1": people say "檯燈" (2026-11-11: 「檯燈打開」 fell back to
        # the generic 燈 and asked about other lamps).
        short = re.sub(r"\s*(插座|socket|plug|outlet)\s*\d*$", "", name, flags=re.I).strip()
        if short and short != name and short not in aliases:
            aliases.append(short)
        aname = areas.get(area, "") if area else ""
        if aname and name.startswith(aname) and len(name) > len(aname):
            aliases.append(name[len(aname):])           # "主臥燈" also answers to "燈" within 主臥
        features = []
        modes = attrs.get("supported_color_modes") or []
        if domain == "light" and any(m != "onoff" for m in modes):
            features.append("brightness")
        nlu_domain = "light" if (domain == "switch" and "燈" in name) else domain
        e = {"entity_id": eid, "name": name, "aliases": aliases, "area": area, "domain": nlu_domain,
             "ha_domain": domain, "features": features, "allowed": online}
        if domain == "climate":
            e["min_temp"] = attrs.get("min_temp", 16)
            e["max_temp"] = attrs.get("max_temp", 30)
        home["entities"].append(e)
        s = {"state": "off" if st.get("state") == "off" else st.get("state")}
        if domain == "light" and attrs.get("brightness") is not None:
            s["brightness_pct"] = round(attrs["brightness"] / 2.55)
        if domain == "climate" and attrs.get("temperature") is not None:
            s["temperature"] = attrs["temperature"]
        if domain == "fan" and attrs.get("percentage") is not None:
            s["percentage"] = attrs["percentage"]
        home["state"][eid] = s
    return home


def service_for(ha_domain, op, value=None):
    """NLU op (validate() output) -> (domain, service, data)."""
    if op in ("turn_on", "turn_off"):
        if ha_domain == "cover":
            return "cover", "open_cover" if op == "turn_on" else "close_cover", {}
        return ha_domain, op, {}
    if op == "set_brightness":
        return "light", "turn_on", {"brightness_pct": value}
    if op == "set_temperature":
        return "climate", "set_temperature", {"temperature": value}
    if op == "set_percentage":
        return "fan", "set_percentage", {"percentage": value}
    if op == "open":
        return "cover", "open_cover", {}
    if op == "close":
        return "cover", "close_cover", {}
    if op == "set_position":
        return "cover", "set_cover_position", {"position": value}
    if op in ("lock", "unlock"):
        return "lock", op, {}
    raise ValueError(f"unsupported op {op}")


def service_timeout(domain):
    """Seconds to wait for HA to confirm a service call. Curtain robots (BLE) can take far longer than lights."""
    return 30 if domain == "cover" else 8


def toggle_service(eid, state):
    domain = eid.split(".", 1)[0]
    on = state in ON_STATES
    if domain == "cover":
        return "cover", "close_cover" if on else "open_cover"
    return domain, "turn_off" if on else "turn_on"
