#!/usr/bin/env python3
"""Constrained-slot NLU: the LLM only picks from small closed sets, rules do
the rest (user's proposal, 2026-11-09).

The model never writes entity_ids, ops or free-form values. Its JSON is
grammar-limited to:
  intent  ∈ {控制, 反問, 拒絕}
  items[] = {device ∈ registry names/aliases ∪ generic words,
             room ∈ areas ∪ {未指定}, action ∈ 12 verbs,
             scope ∈ {單一, 全部}, exclude: bool, amount: number?}
A deterministic resolver (shared with nlu_rules.RuleParser) maps that to
entity_ids and HA ops; numbers come from the text by code whenever possible;
ambiguity follows the same ask-first policy as the rules parser.
"""
import json
import re
import time
import urllib.request

from nlu_rules import RuleParser, cn_num

GENERIC = {"燈": "light", "冷氣": "climate", "風扇": "fan", "窗簾": "cover", "門鎖": "lock"}
OTHER = "其他設備"
ACTIONS = {"開": "on", "關": "off", "調亮": "adjust_light+", "調暗": "adjust_light-", "調高溫度": "adjust_temp+",
           "調低溫度": "adjust_temp-", "設定數值": "set", "最大": "max", "最小": "min", "一半": "set_pct50",
           "上鎖": "lock", "解鎖": "unlock"}

SYSTEM = """你負責理解臥室／客廳等家電的臺灣中文指令，只從固定選項中挑選，輸出 JSON。
intent：控制（要操作設備）／反問（不知道哪個設備或缺數值）／拒絕（查詢、排程、閒聊、沒有的設備或功能）。
items：每個要操作的設備一項。
- device：從選項挑；有指定名稱就挑名稱，只說「燈」「冷氣」這類就挑通用詞；清單沒有的設備挑「其他設備」。
- room：使用者有說區域才填，否則「未指定」。
- action：開／關／調亮／調暗／調高溫度／調低溫度／設定數值／最大／最小／一半／上鎖／解鎖。
- scope：說「全部、所有、都」= 全部，否則 單一。
- exclude：「除了 X」「不要關 X」的 X 填 true。
- amount：句子裡的數字（度數、百分比）；沒有就不要填。
使用者改口（「不對，是…」）只保留改口後的設備。
間接說法：「好暗」= 調亮；「好熱」= 調低溫度；「好冷」= 調高溫度。
裝置選項：{devices}
區域選項：{rooms}"""

FEWSHOT = [
    ("把臥室窗簾關到一半", {"intent": "控制", "items": [{"device": "臥室窗簾", "room": "臥室", "action": "一半", "scope": "單一"}]}),
    ("客廳主燈暗一點，電扇開到40%", {"intent": "控制", "items": [
        {"device": "客廳主燈", "room": "客廳", "action": "調暗", "scope": "單一"},
        {"device": "客廳電風扇", "room": "客廳", "action": "設定數值", "scope": "單一", "amount": 40}]}),
    ("廚房好暗", {"intent": "控制", "items": [{"device": "燈", "room": "廚房", "action": "調亮", "scope": "全部"}]}),
    ("除了小夜燈，燈都關掉", {"intent": "控制", "items": [
        {"device": "小夜燈", "room": "未指定", "action": "關", "scope": "單一", "exclude": True},
        {"device": "燈", "room": "未指定", "action": "關", "scope": "全部"}]}),
    ("打開客廳燈條，不對，是廚房燈", {"intent": "控制", "items": [{"device": "廚房燈", "room": "廚房", "action": "開", "scope": "單一"}]}),
    ("冷氣開", {"intent": "反問", "items": []}),
    ("半小時後關冷氣", {"intent": "拒絕", "items": []}),
    ("車庫門打開", {"intent": "拒絕", "items": [{"device": "其他設備", "room": "未指定", "action": "開", "scope": "單一"}]}),
]


# Off-list `action` values the model may emit -> fixed action (checked in order; first match wins).
INDIRECT = [
    (("熱", "降溫", "涼"), "調低溫度"),
    (("冷", "升溫", "暖"), "調高溫度"),
    (("暗",), "調亮"),
    (("亮", "刺眼"), "調暗"),
    (("打開", "開啟", "開一下"), "開"),
    (("關掉", "關閉", "關上"), "關"),
]
SHORT = {"intent": "i", "items": "x", "device": "d", "room": "r", "action": "a", "scope": "s",
         "exclude": "e", "amount": "n"}
LONG = {v: k for k, v in SHORT.items()}


def _rekey(obj, table):
    if isinstance(obj, dict):
        return {table.get(k, k): _rekey(v, table) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_rekey(v, table) for v in obj]
    return obj


def _compact_example(a):
    """Short keys, drop defaults (scope 單一, room 未指定) to cut output tokens."""
    out = {"intent": a["intent"], "items": []}
    for it in a["items"]:
        it = dict(it)
        if it.get("scope") == "單一":
            it.pop("scope")
        if it.get("room") == "未指定":
            it.pop("room")
        out["items"].append(it)
    if not out["items"]:
        out.pop("items")
    return _rekey(out, SHORT)


class SlotParser:
    """compact=True: one-letter keys and optional default fields
    (i/x/d/r/a/s/e/n), so the model emits roughly half the tokens."""

    def __init__(self, home, url, compact=False):
        self.home, self.url, self.compact = home, url, compact
        self.rp = RuleParser(home)
        self.by_id = self.rp.by_id
        self.name2id = {}
        for e in home["entities"]:
            for s in [e["name"]] + e.get("aliases", []):
                self.name2id[s] = e["entity_id"]
        self.room2area = {n: aid for aid, ns in home["areas"].items() for n in ns}
        self.devices = list(self.name2id) + list(GENERIC) + [OTHER]
        self.rooms = list(self.room2area) + ["未指定"]
        item = {"type": "object", "properties": {
            "device": {"enum": self.devices}, "room": {"enum": self.rooms}, "action": {"enum": list(ACTIONS)},
            "scope": {"enum": ["單一", "全部"]}, "exclude": {"type": "boolean"}, "amount": {"type": "number"}},
            "required": ["device", "room", "action", "scope"], "additionalProperties": False}
        self.schema = {"type": "object", "properties": {"intent": {"enum": ["控制", "反問", "拒絕"]},
                                                        "items": {"type": "array", "items": item}},
                       "required": ["intent", "items"], "additionalProperties": False}
        self.system = SYSTEM.format(devices="、".join(self.devices), rooms="、".join(self.rooms))
        if compact:  # build explicitly: _rekey would also rename the JSON-schema keyword "items"
            citem = {"type": "object", "properties": {SHORT[k]: v for k, v in item["properties"].items()},
                     "required": ["d", "a"], "additionalProperties": False}
            self.schema = {"type": "object", "properties": {"i": {"enum": ["控制", "反問", "拒絕"]},
                                                            "x": {"type": "array", "items": citem}},
                           "required": ["i"], "additionalProperties": False}
            self.system += ("\n輸出用縮寫鍵：i=intent，x=items，d=device，r=room，a=action，s=scope，e=exclude，n=amount。"
                            "room 是「未指定」、scope 是「單一」時省略不寫；沒有動作時省略 x。")

    def ask(self, text):
        msgs = [{"role": "system", "content": self.system}]
        for q, a in FEWSHOT:
            a = _compact_example(a) if self.compact else a
            msgs += [{"role": "user", "content": q}, {"role": "assistant", "content": json.dumps(a, ensure_ascii=False, separators=(",", ":"))}]
        msgs.append({"role": "user", "content": self.rp.normalize(text)})
        body = {"messages": msgs, "temperature": 0, "max_tokens": 200,
                "response_format": {"type": "json_object", "schema": self.schema},
                "chat_template_kwargs": {"enable_thinking": False}}
        req = urllib.request.Request(self.url.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=300) as r:
            resp = json.load(r)
        c = re.sub(r"<think>.*?</think>", "", resp["choices"][0]["message"]["content"], flags=re.S).strip()
        try:
            out = json.loads(c)
            if self.compact:
                out = _rekey(out, LONG)
                out.setdefault("items", [])
                for it in out["items"]:
                    it.setdefault("room", "未指定")
                    it.setdefault("scope", "單一")
            return out, resp.get("timings", {})
        except json.JSONDecodeError:
            return {"intent": "拒絕", "items": []}, resp.get("timings", {})

    def _valid(self, slots):
        """Schema check in code: engines without grammar-constrained decoding (MNN) can emit values outside
        the fixed options (e.g. action "調濕"). Anything off-schema must never execute."""
        if not isinstance(slots, dict) or slots.get("intent") not in ("控制", "反問", "拒絕"):
            return False
        items = slots.get("items", [])
        if not isinstance(items, list):
            return False
        for it in items:
            if not isinstance(it, dict):
                return False
            if it.get("device") not in self.devices or it.get("action") not in ACTIONS:
                return False
            if it.get("room", "未指定") not in self.rooms or it.get("scope", "單一") not in ("單一", "全部"):
                return False
            if "exclude" in it and not isinstance(it["exclude"], bool):
                return False
            if it.get("amount") is not None and not isinstance(it["amount"], (int, float)):
                return False
        return True

    @staticmethod
    def _normalize_actions(slots):
        """Without grammar-constrained decoding the model sometimes copies the user's words into `action`
        (seen on the phone 2026-11-11: Qwen3-1.7B on MNN answered 好熱喔 with action "好熱", intent 反問).
        Map such indirect phrasings and plain verb variants onto the fixed action set; an indirect cue that
        names a concrete adjustment also means the user wants control, not a follow-up question."""
        if not isinstance(slots, dict) or not isinstance(slots.get("items"), list):
            return slots
        cued = False
        for it in slots["items"]:
            if not isinstance(it, dict) or it.get("action") in ACTIONS:
                continue
            a = str(it.get("action", ""))
            for words, target in INDIRECT:
                if any(w in a for w in words):
                    it["action"] = target
                    cued = True
                    break
        if cued and slots.get("intent") == "反問":
            slots["intent"] = "控制"
        return slots

    def resolve(self, slots, text):
        """slots JSON -> proposal (same format as the other backends)."""
        slots = self._normalize_actions(slots)
        if not self._valid(slots):
            return {"actions": [], "clarify": "我不確定要怎麼做，可以再說一次嗎？", "invalid": True}
        if slots.get("intent") == "反問":
            return {"actions": [], "clarify": "請問要控制哪個設備、調成多少？"}
        if slots.get("intent") != "控制" or not slots.get("items"):
            return {"actions": [], "reject": "不支援或不是家電控制"}
        nums = [float(n) for n in re.findall(r"\d+(?:\.\d+)?", cn_num(self.rp.normalize(text)))]
        excluded, groups = set(), []
        for it in slots["items"]:
            dev, room = it.get("device"), it.get("room", "未指定")
            if dev == OTHER:
                return {"actions": [], "reject": "沒有這個設備"}
            if dev in self.name2id:
                ids, generic = [self.name2id[dev]], False
            else:
                dom = GENERIC.get(dev)
                area = self.room2area.get(room)
                ids = [e["entity_id"] for e in self.home["entities"]
                       if e["domain"] == dom and (area is None or e["area"] == area)]
                generic = True
            if it.get("exclude"):
                excluded |= set(ids)
                continue
            groups.append((it, ids, generic))
        actions = []
        for it, ids, generic in groups:
            ids = [i for i in ids if i not in excluded]
            act = ACTIONS[it["action"]]
            kind, val = act.rstrip("+-"), None
            amount = it.get("amount")
            if amount is not None and nums and amount not in nums and len(nums) == 1:
                amount = nums[0]  # numbers come from code, not from the model
            if kind == "set":
                if amount is None:
                    if len(nums) == 1:
                        amount = nums[0]
                    else:
                        return {"actions": [], "clarify": "要設成多少呢？"}
                val = amount
                if "%" in cn_num(text) or "百分之" in text:
                    kind = "set_pct"
            elif kind == "adjust_light":
                val = (amount or 20) * (1 if act.endswith("+") else -1)
            elif kind == "adjust_temp":
                val = (amount or 1) * (1 if act.endswith("+") else -1)
            elif kind == "set_pct50":
                kind, val = "set_pct", 50
            if generic and len(ids) > 1 and it.get("scope") != "全部" and kind not in ("off", "close", "lock") \
                    and self.room2area.get(it.get("room")) is None:
                names = "、".join(self.by_id[i]["name"] for i in ids[:3])
                return {"actions": [], "clarify": f"請問是哪一個：{names}？"}
            if not ids:
                return {"actions": [], "reject": "這個區域沒有這類設備"}
            for i in ids:
                if kind == "adjust_light" and "brightness" not in self.by_id[i].get("features", []):
                    if act.endswith("+"):   # 好暗 / 調亮 on an on-off-only light: switch it on
                        actions.append({"entity_id": i, "op": "turn_on"})
                    continue                # 調暗 on an on-off light stays a question, never an off
                op, v = self.rp.ops_for(kind, val, i)
                if op and kind == "adjust_temp" and self.home.get("state", {}).get(i, {}).get("state") == "off":
                    actions.append({"entity_id": i, "op": "turn_on"})   # 好熱 with the AC off: switch it on too
                if op:
                    a = {"entity_id": i, "op": op}
                    if v is not None:
                        a["value"] = v
                    actions.append(a)
        if not actions:
            return {"actions": [], "clarify": "我不確定要怎麼做，可以再說一次嗎？"}
        return {"actions": actions}

    def parse(self, text):
        t0 = time.time()
        slots, tm = self.ask(text)
        prop = self.resolve(slots, text)
        prop["_slots"] = slots
        return prop, time.time() - t0, tm
