#!/usr/bin/env python3
"""Rewrite NLU (user's idea, 2026-11-11): the LLM only paraphrases what the user said into the shortest
canonical command ("冷氣關", "房間燈開", "冷氣調到26度"), and the deterministic rule parser executes that.

Why: with the constrained-slot JSON the model generates 19-60 tokens per sentence (2-7 s on the phone); a
canonical command is 3-10 tokens. The rule parser still decides which entity is meant and validate() still
guards every action, so a paraphrase the rules cannot resolve becomes a question, never a guess.
Special outputs: 反問 (unclear what to do) and 拒絕 (not home control).
"""
import json
import re
import time
import urllib.request

from nlu_rules import RuleParser

SYSTEM = """你負責把使用者對家電說的話，改寫成最短的標準家電指令，交給程式執行。只輸出指令本身，不要解釋。
格式：[區域]裝置動作。多個指令用「，」分開。例如：冷氣關、臥室燈開、冷氣調到26度、燈全部關、窗簾一半。
動作只能用：開、關、調亮、調暗、調高溫度、調低溫度、調到N度、調到N%、一半、最大、最小、全部開、全部關。
裝置只能用清單裡的名稱，或通用詞：燈、冷氣、風扇、窗簾。
間接說法要改寫成動作：好熱 = 冷氣調低溫度；好冷 = 冷氣調高溫度；好暗 = 燈開；太亮 = 燈調暗。
「除了 X」保留成「除了X以外，…」。使用者改口時只保留改口後的指令。
想聽音樂：輸出「播放 歌名、歌手或音樂類型」；暫停、繼續、下一首、上一首、換一個照原樣輸出。
不知道要控制哪個裝置或要做什麼：只輸出「反問」。
不是家電控制（天氣、時間、聊天、排程、清單沒有的裝置或功能）：只輸出「拒絕」。
裝置：{devices}
區域：{rooms}"""

FEWSHOT = [
    ("把臥室窗簾關到一半", "臥室窗簾一半"),
    ("客廳的燈暗一點，風扇開到40%", "客廳燈調暗，風扇調到40%"),
    ("好熱喔", "冷氣調低溫度"),
    ("房間好暗", "臥室燈開"),
    ("除了床頭燈，其他燈都關掉", "除了床頭燈以外，燈全部關"),
    ("打開客廳的燈，不對，是廚房的燈", "廚房燈開"),
    ("冷氣幫我開到二十六度", "冷氣調到26度"),
    ("放點適合讀書的音樂", "播放 讀書音樂"),
    ("我想聽一些輕鬆的歌", "播放 輕鬆音樂"),
    ("我要出門了", "反問"),
    ("半小時後關冷氣", "拒絕"),
    ("明天天氣如何", "拒絕"),
]


class RewriteParser:
    def __init__(self, home, url):
        self.home, self.url = home, url
        self.rp = RuleParser(home)
        names = []
        for e in home["entities"]:
            for n in [e["name"]] + list(e.get("aliases", [])):
                if n and n not in names:
                    names.append(n)
        rooms = []
        for ns in home["areas"].values():
            rooms += [n for n in ns if n not in rooms]
        self.system = SYSTEM.format(devices="、".join(names), rooms="、".join(rooms))

    def ask(self, text):
        msgs = [{"role": "system", "content": self.system}]
        for q, a in FEWSHOT:
            msgs += [{"role": "user", "content": q}, {"role": "assistant", "content": a}]
        msgs.append({"role": "user", "content": self.rp.normalize(text)})
        body = {"messages": msgs, "temperature": 0, "max_tokens": 40,
                "chat_template_kwargs": {"enable_thinking": False}}
        req = urllib.request.Request(self.url.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=300) as r:
            resp = json.load(r)
        out = re.sub(r"<think>.*?</think>", "", resp["choices"][0]["message"]["content"], flags=re.S).strip()
        out = out.splitlines()[0].strip().strip("「」\"'。.") if out else ""
        return out, resp.get("timings", {})

    def _ac_on_first(self, prop):
        """好熱 with the AC off: the rules turn 調低溫度 into a set_temperature; switch the AC on as well."""
        state = self.home.get("state", {})
        out = []
        for a in prop.get("actions", []):
            if a.get("op") == "adjust_temperature" and \
                    state.get(a["entity_id"], {}).get("state") == "off" and \
                    not any(b["entity_id"] == a["entity_id"] and b["op"] == "turn_on" for b in out):
                out.append({"entity_id": a["entity_id"], "op": "turn_on"})
            out.append(a)
        prop["actions"] = out
        return prop

    NOT_UNDERSTOOD = "不能理解，請重新再說一次"

    def _strict_parse(self, rw):
        """Execute a rewrite only if the rules understand *every* clause of it. Found in eval 2026-11-11:
        「把客廳主燈調成暖色」(unsupported) was rewritten to 「客廳燈調亮，客廳燈調暖」; the rules understood the
        first clause, ignored the second and brightened two lamps. One clause the rules cannot read means the
        rewrite is not trustworthy as a whole."""
        clauses = [rw] if "除了" in rw else [c for c in re.split(r"[，,、；;]", rw) if c.strip()]
        for c in clauses:
            r = self.rp.parse(c)
            if r.get("clarify"):
                return {"actions": [], "clarify": r["clarify"]}       # e.g. which of two ACs
            if r.get("_conf") != "high" or (not r.get("actions") and r.get("reject")):
                return {"actions": [], "clarify": self.NOT_UNDERSTOOD, "_unparsed": c}
        prop = self.rp.parse(rw)
        if prop.get("_conf") != "high" or prop.get("reject"):
            return {"actions": [], "clarify": self.NOT_UNDERSTOOD}
        return self._ac_on_first(prop)

    def parse(self, text):
        t0 = time.time()
        rw, tm = self.ask(text)
        if not rw or rw.startswith("反問"):
            prop = {"actions": [], "clarify": self.NOT_UNDERSTOOD}
        elif rw.startswith("拒絕"):
            prop = {"actions": [], "reject": "這不是家電控制，我做不到"}
        else:
            prop = self._strict_parse(rw)
        prop["_rewrite"] = rw
        return prop, time.time() - t0, tm
