#!/usr/bin/env python3
"""Deterministic zh-TW command parser (the "rules first" half of the hybrid NLU).

Produces the same proposal JSON as the LLM backend so validate() stays the
single gate before anything reaches Home Assistant. Every proposal carries
`_conf`: "high" when the sentence was fully understood (actions, a
clarification or a rejection with a concrete reason) and "low" when the
rules gave up; the hybrid backend sends only "low" sentences to the LLM.

Design rules (see README):
- ambiguous targets ask, except turn_off on a whole domain (turning things
  off is the safe direction): 「冷氣也關」 turns every air conditioner off;
- if any clause needs clarification nothing is executed (all-or-nothing);
- ASR homophones of registry words are repaired through toneless pinyin
  (客聽→客廳, 床投燈→床頭燈, 臥式→臥室, 主等→主燈); 杜→度 after a number.
"""
import re

import os

try:
    from pypinyin import lazy_pinyin
except ImportError:  # pragma: no cover
    # Without pypinyin, ASR homophones are not repaired (e.g. 客聽 is not recognised as 客廳, so "客聽的燈全部
    # 關掉" turned off every light in the house on the phone). Never degrade silently.
    if os.environ.get("NLU_ALLOW_NO_PINYIN") != "1":
        raise ImportError("nlu_rules requires pypinyin for ASR homophone repair "
                          "(apt install python3-pypinyin); set NLU_ALLOW_NO_PINYIN=1 only for tests")
    lazy_pinyin = None

try:
    import opencc
    _S2T = opencc.OpenCC("s2twp")
except Exception:  # pragma: no cover
    _S2T = None

CN = {"零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
DOMAIN_WORDS = [  # longest first
    ("電風扇", "fan"), ("風扇", "fan"), ("電扇", "fan"), ("冷氣", "climate"), ("空調", "climate"),
    ("窗簾", "cover"), ("門鎖", "lock"), ("大門", "lock"), ("燈光", "light"), ("照明", "light"),
    ("燈", "light"), ("門", "lock"),
]
FILLERS = r"幫我|麻煩|請|把|將|給我|一下|一盞|的|了|啦|喔|吧|呢|好嗎|可以嗎|欸|那個|這個|那邊|這邊|我|你|都|也|全部|全|所有|其他|再|順便|然後|就|先|還有|跟|和|及|，|、"
SPLIT = r"[，,。；;！!？?\s]+|然後|順便|接著|再來|還有|另外"


def cn_num(s):
    def conv(m):
        t = m.group(0)
        if t == "十":
            return "10"
        if "十" in t:
            a, b = t.split("十", 1)
            return str((CN.get(a, 1) if a else 1) * 10 + (CN.get(b, 0) if b else 0))
        if len(t) == 2:
            return str(CN[t[0]] * 10 + CN[t[1]])
        return str(CN[t])
    s = re.sub(r"百分之([零一二兩三四五六七八九十]+)", lambda m: cn_num(m.group(1)) + "%", s)
    s = re.sub(r"[一二兩三四五六七八九]?十[一二三四五六七八九]?|[一二三四五六七八九]{2}(?=度|$)|[一二兩三四五六七八九](?=度)", conv, s)
    return s.replace("％", "%").replace("趴", "%")


class RuleParser:
    def __init__(self, home):
        self.home = home
        self.ents = home["entities"]
        self.by_id = {e["entity_id"]: e for e in self.ents}
        self.state = home.get("state", {})
        self.areas = {}  # surface -> area id
        for aid, names in home["areas"].items():
            for n in names:
                self.areas[n] = aid
        surf = {}
        for e in self.ents:
            for s in [e["name"]] + e.get("aliases", []):
                surf.setdefault(s, set()).add(e["entity_id"])
        # name minus its area prefix (客廳燈條 -> 燈條) when that is unique
        short = {}
        for e in self.ents:
            for s in [e["name"]] + e.get("aliases", []):
                for a in self.areas:
                    if s.startswith(a) and len(s) - len(a) >= 2:
                        short.setdefault(s[len(a):], set()).add(e["entity_id"])
        for s, ids in short.items():
            if len(ids) == 1 and s not in surf and s not in dict(DOMAIN_WORDS):
                surf[s] = ids
        self.surfaces = sorted(((s, sorted(ids)) for s, ids in surf.items() if len(ids) == 1),
                               key=lambda x: -len(x[0]))
        vocab = set(surf) | set(self.areas)
        self.vocab = sorted(vocab, key=len, reverse=True)
        self._py = {w: self._pinyin(w) for w in self.vocab} if lazy_pinyin else {}

    # ------------------------------------------------------------ text prep
    @staticmethod
    def _pinyin(s):
        return [lazy_pinyin(c)[0] for c in s] if lazy_pinyin else list(s)

    def repair(self, text):
        """Replace homophones of registry words (ASR errors)."""
        if not lazy_pinyin:
            return text
        out, i = [], 0
        py = [self._pinyin(c)[0] if c.strip() else c for c in text]  # per char: digits stay aligned
        while i < len(text):
            for w in self.vocab:
                L = len(w)
                if L >= 2 and text[i:i + L] != w and py[i:i + L] == self._py[w]:
                    out.append(w)
                    i += L
                    break
            else:
                out.append(text[i])
                i += 1
        return "".join(out)

    def normalize(self, text):
        if _S2T:
            text = _S2T.convert(text)
        text = cn_num(text)
        text = self.repair(text)
        text = re.sub(r"(\d)\s*[杜渡肚]", r"\1度", text)
        return re.sub(r"(\d)\s+度", r"\1度", text)

    # ------------------------------------------------------------ targets
    def find_targets(self, clause):
        """Return (targets, rest). A target is dict(ids=[...], kind=entity|group|domain|area, domain)."""
        rest, targets = clause, []
        for s, ids in self.surfaces:
            if s in rest:
                rest = rest.replace(s, "　")
                targets.append({"ids": ids, "kind": "entity", "domain": self.by_id[ids[0]]["domain"]})
        for a, aid in sorted(self.areas.items(), key=lambda x: -len(x[0])):
            m = re.search(re.escape(a) + r"(?:的|那邊的|裡的)?(" + "|".join(w for w, _ in DOMAIN_WORDS) + ")?", rest)
            if not m:
                continue
            dom = dict(DOMAIN_WORDS).get(m.group(1)) if m.group(1) else None
            ids = [e["entity_id"] for e in self.ents if e["area"] == aid and (dom is None or e["domain"] == dom)]
            rest = rest[:m.start()] + "　" + rest[m.end():]
            targets.append({"ids": ids, "kind": "group" if dom else "area", "domain": dom, "area": aid})
        for w, dom in DOMAIN_WORDS:
            if w in rest:
                ids = [e["entity_id"] for e in self.ents if e["domain"] == dom]
                rest = rest.replace(w, "　", 1)
                targets.append({"ids": ids, "kind": "domain", "domain": dom})
        return targets, rest

    # ------------------------------------------------------------ verbs
    @staticmethod
    def parse_verb(rest, full):
        """Return (op_kind, value) where op_kind is one of
        on/off/open/close/lock/unlock/set/set_pct/adjust_light/adjust_temp/half/min/max/missing or None."""
        num = re.search(r"(\d+(?:\.\d+)?)\s*(%|度)?", rest)
        if re.search(r"鎖(上|起來|好|住)", full):
            return "lock", None
        if re.search(r"解鎖", full):
            return "unlock", None
        if "減半" in rest or "一半" in rest and "亮" in rest:
            return "half", None
        if "一半" in rest:
            return "set_pct", 50
        if re.search(r"最(大|亮|強|高)", rest):
            return "max", None
        if re.search(r"最(小|暗|弱|低)", rest):
            return "min", None
        if re.search(r"(調|再|升|降|溫度)?(高|低|升|降)", rest) and (num and num.group(2) == "度" or re.search(r"(調|再|升|降)(高|低)?|(高|低)(一點|一些|點|些)", rest)):
            sign = 1 if re.search(r"高|升|加", rest) else -1
            return "adjust_temp", sign * (float(num.group(1)) if num else 1)
        if re.search(r"(調|再|變)(亮|暗)|(亮|暗)(一點|一些|點|些)", rest):
            return "adjust_light", 20 if "亮" in rest else -20
        if num:
            return ("set_pct" if num.group(2) == "%" else "set"), float(num.group(1))
        if re.search(r"調一下|調整", rest) or re.search(r"(亮度|溫度)$", rest.strip("　")):
            return "missing", None
        if re.search(r"拉起來|拉上|關上|關起來|放下", rest):
            return "close", None
        if re.search(r"拉開|打開|開", rest) and re.search(r"窗簾", full):
            return "open", None
        if re.search(r"關|熄", rest):
            return "off", None
        if re.search(r"開|啟動|留|亮起來", rest):
            return "on", None
        return None, None

    # ------------------------------------------------------------ resolve
    def ops_for(self, kind, val, eid):
        e = self.by_id[eid]
        d, st = e["domain"], self.state.get(eid, {})
        if kind == "off":
            return {"cover": "close", "lock": "lock"}.get(d, "turn_off"), None
        if kind == "on":
            return {"cover": "open", "lock": "unlock"}.get(d, "turn_on"), None
        if kind == "open":
            return ("open" if d == "cover" else "unlock" if d == "lock" else "turn_on"), None
        if kind == "close":
            return ("close" if d == "cover" else "lock" if d == "lock" else "turn_off"), None
        if kind in ("lock", "unlock"):
            return (kind, None) if d == "lock" else (None, None)
        if kind == "adjust_temp":
            return ("adjust_temperature", val) if d == "climate" else (None, None)
        if kind == "adjust_light":
            return ("adjust_brightness", val) if d == "light" and "brightness" in e.get("features", []) else (None, None)
        pct_op = {"light": "set_brightness", "fan": "set_percentage", "cover": "set_position"}.get(d)
        if kind == "half" and d == "light":
            return "set_brightness", max(1, round(st.get("brightness_pct", 100) / 2))
        if kind == "max":
            return (pct_op, 100) if pct_op else ("set_temperature", e.get("max_temp", 30)) if d == "climate" else (None, None)
        if kind == "min":
            return (pct_op, 1 if d == "light" else 0) if pct_op else ("set_temperature", e.get("min_temp", 16)) if d == "climate" else (None, None)
        if kind == "set_pct":
            return (pct_op, val) if pct_op else (None, None)
        if kind == "set":
            return ("set_temperature", val) if d == "climate" else (pct_op, val) if pct_op else (None, None)
        return None, None

    # Linguistic cues the rules cannot handle safely: schedules, self-corrections,
    # questions about state. Their result is marked low-confidence so the hybrid
    # backends hand the sentence to the LLM (added after tests-web; see report §6).
    DEFER = re.compile(r"(\d+|[一二兩三四五六七八九十半]+)(秒|分鐘|分|小時|個小時)(後|以後|之後)|明天|待會|等一下再|"
                       r"不對|不是|我是說|改成|幾度|多少|有沒有|是不是|了沒|嗎$|呢$")

    def parse(self, text):
        r = self._parse(text)
        # NOTE: also deferring the rules' clarify answers was tried and made things worse
        # (the LLM then guesses and executes: wrong_executed 3 -> 11), so clarify stays final.
        if self.DEFER.search(self.normalize(text)):
            r["_conf"] = "low"
        return r

    def _parse(self, text):
        t = self.normalize(text)
        excluded = set()
        m = re.search(r"除了(.+?)(之外|以外)", t)
        if m:
            for tg in self.find_targets(m.group(1))[0]:
                excluded |= set(tg["ids"])
            t = t[:m.start()] + t[m.end():]
        clauses = [c for c in re.split(SPLIT, t) if c]
        actions, clarify, unknown, carry = [], None, None, []
        understood = False
        for c in clauses:
            targets, rest = self.find_targets(c)
            kind, val = self.parse_verb(rest, c)
            if not kind:
                if targets:
                    carry = targets  # e.g. 「客廳有點暗，幫我調亮一點」
                continue
            understood = True
            if not targets and carry:
                targets, carry = carry, []
            if kind == "missing":
                clarify = clarify or "要調成多少呢？"
                continue
            if not targets:
                left = re.sub(FILLERS, "", re.sub(r"\d+(\.\d+)?(%|度)?|打開|關掉|關閉|開|關|熄掉|熄|調亮|調暗|調高|調低|亮|暗|一點|一些|起來|上|到|設定|設|調", "", rest))
                left = left.replace("　", "")
                if len(left) >= 2:
                    unknown = f"找不到「{left}」這個設備"
                else:
                    clarify = clarify or "請問要控制哪個設備？"
                continue
            for tg in targets:
                ids = [i for i in tg["ids"] if i not in excluded]
                dom = tg["domain"]
                if tg["kind"] == "area":  # area without device word: infer from verb
                    want = {"adjust_light": "light", "half": "light", "adjust_temp": "climate"}.get(kind)
                    if not want:
                        clarify = clarify or "請問是哪個設備？"
                        continue
                    ids = [i for i in ids if self.by_id[i]["domain"] == want]
                    if want == "light":
                        ids = [i for i in ids if "brightness" in self.by_id[i].get("features", [])]
                if tg["kind"] == "domain" and len(ids) > 1 and kind not in ("off", "close", "lock"):
                    if "其他" in c or "全" in c or "所有" in c:
                        pass  # explicit "all": allowed for every op
                    else:
                        names = "、".join(self.by_id[i]["name"] for i in ids[:3])
                        clarify = clarify or f"請問是哪一個：{names}？"
                        continue
                if tg["kind"] == "domain" and dom == "light" and len(ids) > 1 and not re.search(r"其他|全|所有|都", c):
                    clarify = clarify or "請問要關哪一盞燈？"
                    continue
                for i in ids:
                    op, v = self.ops_for(kind, val, i)
                    if op is None:
                        continue
                    a = {"entity_id": i, "op": op}
                    if v is not None:
                        a["value"] = v
                    actions.append(a)
        if clarify:
            return {"actions": [], "clarify": clarify, "_conf": "high"}
        if actions:
            return {"actions": actions, "_conf": "high"}
        if unknown:
            return {"actions": [], "reject": unknown, "_conf": "high"}
        if not understood:
            return {"actions": [], "reject": "不是家電控制指令", "_conf": "low"}
        return {"actions": [], "reject": "無法解析", "_conf": "low"}
