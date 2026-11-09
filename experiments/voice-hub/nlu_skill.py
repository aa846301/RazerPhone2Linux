#!/usr/bin/env python3
""""Skill" prompting for small local LLMs (A: per-domain skill cards,
B: retrieved few-shot examples).

Small models follow examples much better than long instructions, so instead
of one big system prompt we:
  1. detect which domains the sentence talks about (keywords from the
     registry) and include only those devices and those domain skill cards;
  2. retrieve the k most similar examples from an example bank that is
     generated automatically from the HA registry (so it works for any home)
     and show them as chat turns.

The bank is generated from templates and never contains a sentence from the
test files (checked at build time).
"""
import glob
import json
import os
import random
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CNUM = "零一二三四五六七八九"


def cn(n):
    n = int(n)
    if n < 10:
        return CNUM[n]
    t, o = divmod(n, 10)
    return ("" if t == 1 else CNUM[t]) + "十" + (CNUM[o] if o else "")


DOMAIN_WORDS = {"light": ["燈", "亮", "暗", "燈光"], "climate": ["冷氣", "空調", "度", "溫度", "熱", "冷"],
                "fan": ["風扇", "電扇"], "cover": ["窗簾"], "lock": ["門", "鎖"], "switch": []}

SKILL_CARDS = {
    "light": "燈：turn_on/turn_off；set_brightness value=0-100；亮一點/暗一點用 adjust_brightness ±20；「最亮」=100；「熄掉」=turn_off。",
    "climate": "冷氣：turn_on/turn_off；set_temperature value=攝氏度數；調高/調低用 adjust_temperature，沒說幾度就 ±1；有兩台冷氣又沒說哪台要 clarify（只有關閉可以全部關）。",
    "fan": "風扇：turn_on/turn_off；set_percentage value=0-100，「最大」=100。",
    "cover": "窗簾：open（打開/拉開）/close（關上/拉上）；set_position value=0-100，「一半」=50。",
    "lock": "門鎖：lock（鎖上）/unlock（開門/解鎖）。",
    "switch": "開關：turn_on/turn_off。",
}

SYSTEM = """你是智慧家庭指令解析器。把使用者的臺灣中文指令轉成 JSON，只輸出 JSON。
- actions：要執行的動作陣列，entity_id 只能用下方清單。
- 不知道是哪個設備或缺少數值：actions 留空，clarify 寫一句問句。
- 設備不存在或不是家電指令：actions 留空，reject 寫原因。
- 數字以括號內「程式抽出的數字」為準。
{cards}
設備（entity_id｜名稱／別名｜區域）：
{devices}"""


def _ops(e):
    d = e["domain"]
    if d == "light":
        return ["turn_on", "turn_off"] + (["set_brightness", "adjust_brightness"] if "brightness" in e.get("features", []) else [])
    return {"climate": ["turn_on", "turn_off", "set_temperature", "adjust_temperature"],
            "fan": ["turn_on", "turn_off", "set_percentage"], "cover": ["open", "close", "set_position"],
            "lock": ["lock", "unlock"], "switch": ["turn_on", "turn_off"]}[d]


def act(eid, op, v=None):
    a = {"entity_id": eid, "op": op}
    if v is not None:
        a["value"] = v
    return a


def gen_bank(home, seed=7):
    rnd = random.Random(seed)
    ents = [e for e in home["entities"] if e.get("allowed")]
    area_names = {k: v for k, v in home["areas"].items()}
    out = []

    def add(text, ans):
        out.append((text, ans))

    for e in ents:
        names = [e["name"]] + e.get("aliases", [])
        eid, d = e["entity_id"], e["domain"]
        for n in names:
            if d in ("light", "fan", "switch", "climate"):
                add(rnd.choice(["打開{n}", "把{n}打開", "{n}開一下", "麻煩開一下{n}", "{n}幫我打開"]).format(n=n), {"actions": [act(eid, "turn_on")]})
                add(rnd.choice(["關掉{n}", "把{n}關掉", "{n}關一下", "{n}幫我關了", "麻煩把{n}關起來"]).format(n=n), {"actions": [act(eid, "turn_off")]})
            if d == "light":
                add(rnd.choice(["{n}熄燈", "把{n}熄了"]).format(n=n), {"actions": [act(eid, "turn_off")]})
                if "brightness" in e.get("features", []):
                    v = rnd.choice([15, 20, 35, 45, 60, 70, 85])
                    add(rnd.choice(["{n}亮度調到百分之{c}", "把{n}設成{v}%", "{n}調成{v}趴"]).format(n=n, v=v, c=cn(v)), {"actions": [act(eid, "set_brightness", v)]})
                    add(rnd.choice(["{n}亮一些", "把{n}調亮", "{n}再亮一點點"]).format(n=n), {"actions": [act(eid, "adjust_brightness", 20)]})
                    add(rnd.choice(["{n}太亮了", "{n}調暗", "把{n}弄暗一點"]).format(n=n), {"actions": [act(eid, "adjust_brightness", -20)]})
            if d == "climate":
                v = rnd.choice([20, 21, 22, 23, 24, 25, 26, 27, 28])
                add(rnd.choice(["{n}設定{c}度", "把{n}調到{v}度", "{n}開{c}度就好", "{n}溫度改成{c}"]).format(n=n, v=v, c=cn(v)), {"actions": [act(eid, "set_temperature", v)]})
                k = rnd.choice([1, 2, 3])
                add(rnd.choice(["{n}降{c}度", "把{n}調低{c}度", "{n}溫度減{c}度"]).format(n=n, c=cn(k) if k != 2 else "兩"), {"actions": [act(eid, "adjust_temperature", -k)]})
                add(rnd.choice(["{n}升{c}度", "把{n}溫度加{c}度"]).format(n=n, c=cn(k) if k != 2 else "兩"), {"actions": [act(eid, "adjust_temperature", k)]})
                add(rnd.choice(["{n}有點冷，調高一點", "{n}再暖一點"]).format(n=n), {"actions": [act(eid, "adjust_temperature", 1)]})
                add(rnd.choice(["{n}不夠涼，再低一點", "{n}熱死了調低"]).format(n=n), {"actions": [act(eid, "adjust_temperature", -1)]})
            if d == "fan":
                v = rnd.choice([20, 30, 60, 70, 80])
                add(rnd.choice(["{n}調到百分之{c}", "{n}風速{v}%"]).format(n=n, v=v, c=cn(v)), {"actions": [act(eid, "set_percentage", v)]})
                add(rnd.choice(["{n}開最強", "{n}風開到最大"]).format(n=n), {"actions": [act(eid, "set_percentage", 100)]})
            if d == "cover":
                add(rnd.choice(["{n}拉開", "請把{n}打開", "{n}開起來"]).format(n=n), {"actions": [act(eid, "open")]})
                add(rnd.choice(["{n}拉上", "把{n}關上", "{n}關好"]).format(n=n), {"actions": [act(eid, "close")]})
                v = rnd.choice([25, 30, 70, 75])
                add(rnd.choice(["{n}開到{v}%", "{n}拉到百分之{c}"]).format(n=n, v=v, c=cn(v)), {"actions": [act(eid, "set_position", v)]})
            if d == "lock":
                add(rnd.choice(["把{n}上鎖", "{n}鎖好", "鎖{n}"]).format(n=n), {"actions": [act(eid, "lock")]})
                add(rnd.choice(["{n}解鎖", "幫我把{n}開鎖"]).format(n=n), {"actions": [act(eid, "unlock")]})
    # area groups
    for aid, ns in area_names.items():
        lights = [e["entity_id"] for e in ents if e["area"] == aid and e["domain"] == "light"]
        for n in ns:
            if len(lights) > 1:
                add(rnd.choice(["{a}的燈都關掉", "{a}燈全部關", "把{a}所有的燈關了"]).format(a=n), {"actions": [act(i, "turn_off") for i in lights]})
                add(rnd.choice(["{a}的燈全部打開", "{a}燈都開"]).format(a=n), {"actions": [act(i, "turn_on") for i in lights]})
    alll = [e["entity_id"] for e in ents if e["domain"] == "light"]
    add("全家的燈都關掉", {"actions": [act(i, "turn_off") for i in alll]})
    add("所有燈打開", {"actions": [act(i, "turn_on") for i in alll]})
    # multi
    singles = [x for x in out if len(x[1]["actions"]) == 1]
    for _ in range(40):
        (t1, a1), (t2, a2) = rnd.sample(singles, 2)
        if a1["actions"][0]["entity_id"] == a2["actions"][0]["entity_id"]:
            continue
        j = rnd.choice(["，然後", "，順便", "，再", "，"])
        add(t1 + j + t2, {"actions": a1["actions"] + a2["actions"]})
    # clarify / reject (fake devices and phrasings that are not in the test files)
    by_dom = {}
    for e in ents:
        by_dom.setdefault(e["domain"], []).append(e)
    for d, es in by_dom.items():
        if len(es) < 2:
            continue
        word = {"light": "燈", "climate": "冷氣"}.get(d)
        if not word:
            continue
        names = "、".join(e["name"] for e in es[:3])
        for t in ([f"{word}打開一下", f"開個{word}"] + ([f"{word}調成二十二度", f"{word}升高一點"] if d == "climate" else [f"把{word}調亮", f"{word}亮度五十"])):
            add(t, {"actions": [], "clarify": f"請問是哪一個：{names}？"})
    for t in ["幫我調一下", "那個開一下", "再多一點"]:
        add(t, {"actions": [], "clarify": "請問要控制哪個設備？"})
    for t, why in [("打開書房的燈", "沒有書房的燈"), ("冰箱溫度調低", "沒有冰箱"), ("除濕機打開", "沒有除濕機"),
                   ("車庫門打開", "沒有車庫門"), ("講個笑話", "不是家電指令"), ("明天會下雨嗎", "不是家電指令"),
                   ("幫我訂一個披薩", "不是家電指令"), ("烤箱預熱兩百度", "沒有烤箱")]:
        add(t, {"actions": [], "reject": why})
    # never include a test sentence
    tests = set()
    for p in glob.glob(os.path.join(HERE, "tests*.jsonl")):
        tests |= {json.loads(l)["text"] for l in open(p, encoding="utf-8") if l.strip()}
    seen, bank = set(), []
    for t, a in out:
        if t in tests or t in seen:
            continue
        seen.add(t)
        bank.append((t, a))
    return bank


def bigrams(s):
    s = re.sub(r"[\s，。,.!?！？]", "", s)
    return {s[i:i + 2] for i in range(len(s) - 1)} | set(s)


LONG_RULES = """詳細規則：
1. 一句話可能有多個動作，全部列出；「A 跟 B 都…」要分成兩個動作。
2. 「某區域的燈」= 該區域所有燈；「所有燈／全部的燈」= 每一盞燈；「除了 X」「不要關 X」要排除 X。
3. 使用者改口（「不對，是…」「我是說…」）只執行改口後的內容。
4. 間接說法：「好暗」= 該區域的燈調亮 +20；「好熱／好冷」= 冷氣調低／調高 1 度；沒有區域又有多台設備時要 clarify。
5. 查詢狀態（幾度、有沒有鎖、好了沒）、排程（幾分鐘後、明天早上）、模式或顏色（除濕、暖色）目前都不支援：actions 留空並 reject。
6. 沒有指定設備的「全部關掉」「開一下」要 clarify。
7. 打招呼、閒聊、未定義的場景（晚安、早安）不要產生動作，reject。
8. ASR 可能有同音錯字（客聽=客廳、主等=主燈、臥式=臥室），依設備清單修正；「臥房」=臥室。
9. 溫度單位是攝氏；「百分之三十」= 30；「二六」= 26；「最低／最高溫」用設備的溫度上下限。"""


class Skill:
    """mode="short": domain-filtered devices + matching skill cards + k=6 examples.
    mode="long": every device with state, every card, detailed rules, k=12 examples."""

    def __init__(self, home, k=6, mode="short"):
        self.mode = mode
        k = 12 if mode == "long" else k
        self.home, self.k = home, k
        self.bank = gen_bank(home)
        self.grams = [bigrams(t) for t, _ in self.bank]
        self.area_name = {k: v[0] for k, v in home["areas"].items()}

    def retrieve(self, text):
        g = bigrams(text)
        sc = [(len(g & h) / (len(g | h) or 1), i) for i, h in enumerate(self.grams)]
        sc.sort(reverse=True)
        return [self.bank[i] for _, i in sc[:self.k]]

    def domains(self, text):
        found = set()
        for e in self.home["entities"]:
            if any(s in text for s in [e["name"]] + e.get("aliases", [])):
                found.add(e["domain"])
        for d, ws in DOMAIN_WORDS.items():
            if any(w in text for w in ws):
                found.add(d)
        return found

    def messages(self, text, hint=""):
        if self.mode == "long":
            st = self.home.get("state", {})
            ents = self.home["entities"]
            devices = "\n".join(
                f'{e["entity_id"]}｜{"／".join([e["name"]] + e.get("aliases", []))}｜{self.area_name.get(e["area"], "-")}'
                f'｜{"允許" if e.get("allowed") else "不允許"}｜狀態:{",".join(f"{k}={v}" for k, v in st.get(e["entity_id"], {}).items()) or "-"}'
                + (f'｜溫度範圍{e.get("min_temp")}-{e.get("max_temp")}' if e["domain"] == "climate" else "")
                for e in ents)
            cards = "\n".join(SKILL_CARDS.values()) + "\n" + LONG_RULES
            msgs = [{"role": "system", "content": SYSTEM.format(cards=cards, devices=devices)}]
            for t, a in reversed(self.retrieve(text)):
                msgs += [{"role": "user", "content": t}, {"role": "assistant", "content": json.dumps(a, ensure_ascii=False)}]
            msgs.append({"role": "user", "content": text + hint})
            return msgs, [e["entity_id"] for e in ents]
        doms = self.domains(text)
        ents = [e for e in self.home["entities"] if not doms or e["domain"] in doms or
                any(s in text for s in [e["name"]] + e.get("aliases", []))]
        devices = "\n".join(f'{e["entity_id"]}｜{"／".join([e["name"]] + e.get("aliases", []))}｜{self.area_name.get(e["area"], "-")}'
                            for e in ents)
        cards = "\n".join(SKILL_CARDS[d] for d in sorted({e["domain"] for e in ents}))
        msgs = [{"role": "system", "content": SYSTEM.format(cards=cards, devices=devices)}]
        for t, a in reversed(self.retrieve(text)):  # most similar example last (closest to the question)
            msgs += [{"role": "user", "content": t}, {"role": "assistant", "content": json.dumps(a, ensure_ascii=False)}]
        msgs.append({"role": "user", "content": text + hint})
        return msgs, [e["entity_id"] for e in ents]


if __name__ == "__main__":
    import sys
    home = json.load(open(os.path.join(HERE, "home.json"), encoding="utf-8"))
    s = Skill(home)
    print("bank size", len(s.bank))
    for t in sys.argv[1:]:
        m, ids = s.messages(t)
        print(json.dumps(m, ensure_ascii=False, indent=1))
