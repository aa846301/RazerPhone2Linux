#!/usr/bin/env python3
"""Home Assistant's own local intent matcher (hassil + home-assistant-intents
zh-TW templates) wrapped to emit the same proposal JSON as nlu.py.

This approximates what HA Assist does with "prefer handling commands locally"
without a running HA: entity names/aliases and areas from home.json become
the {name} and {area} slot lists. It does not reproduce HA's area/floor
context or device_class handling, so treat results as an estimate.
"""
from hassil import Intents, recognize
from hassil.intents import TextSlotList
from home_assistant_intents import get_intents

from nlu_rules import cn_num


class HassilParser:
    def __init__(self, home, lang="zh-TW"):
        self.home = home
        self.by_id = {e["entity_id"]: e for e in home["entities"]}
        self.intents = Intents.from_dict(get_intents(lang))
        names = []
        for e in home["entities"]:
            for s in [e["name"]] + e.get("aliases", []):
                names.append((s, e["entity_id"], {"domain": e["domain"]}))
        areas = [(n, aid) for aid, ns in home["areas"].items() for n in ns]
        self.slots = {"name": TextSlotList.from_tuples(names, allow_template=False),
                      "area": TextSlotList.from_tuples(areas, allow_template=False),
                      "floor": TextSlotList.from_tuples([], allow_template=False)}

    def targets(self, ents):
        if "name" in ents:
            return [ents["name"].value]
        dom = ents["domain"].value if "domain" in ents else None
        area = ents["area"].value if "area" in ents else None
        if area is None and dom is None:
            return []
        return [e["entity_id"] for e in self.home["entities"]
                if (area is None or e["area"] == area) and (dom is None or e["domain"] == dom)]

    def parse(self, text):
        r = recognize(cn_num(text).replace("%", ""), self.intents, slot_lists=self.slots)
        if r is None:
            r = recognize(text, self.intents, slot_lists=self.slots)
        if r is None:
            return {"actions": [], "reject": "hassil: no match", "_conf": "low"}
        ents = r.entities
        name = r.intent.name
        ids = self.targets(ents)
        acts = []
        for i in ids:
            d = self.by_id[i]["domain"]
            if name == "HassTurnOn":
                op = {"cover": "open", "lock": "lock"}.get(d, "turn_on")
                acts.append({"entity_id": i, "op": op})
            elif name == "HassTurnOff":
                op = {"cover": "close", "lock": "unlock"}.get(d, "turn_off")
                acts.append({"entity_id": i, "op": op})
            elif name == "HassLightSet" and "brightness" in ents and d == "light":
                acts.append({"entity_id": i, "op": "set_brightness", "value": float(ents["brightness"].value)})
            elif name == "HassClimateSetTemperature" and d == "climate":
                acts.append({"entity_id": i, "op": "set_temperature", "value": float(ents["temperature"].value)})
            elif name == "HassSetPosition" and d == "cover":
                acts.append({"entity_id": i, "op": "set_position", "value": float(ents["position"].value)})
            elif name == "HassFanSetSpeed" and d == "fan":
                v = ents.get("percentage") or ents.get("fan_speed")
                acts.append({"entity_id": i, "op": "set_percentage", "value": float(v.value)})
        if not acts:
            return {"actions": [], "reject": f"hassil: {name} without usable target", "_conf": "low", "_intent": name}
        return {"actions": acts, "_conf": "high", "_intent": name}
