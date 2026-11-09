#!/usr/bin/env python3
"""Offline NLU harness for the Razer Phone 2 voice hub (stdlib only).

Pipeline: text -> parser (LLM via llama.cpp server, or rules) -> proposal JSON
-> validate() -> resolved Home Assistant actions. The parser never talks to
HA; only validate() output would be executed. Entity IDs that are not in the
registry are rejected, never guessed.

Usage:
  nlu.py eval --backend llm --url http://127.0.0.1:8080 [--tests tests.jsonl]
  nlu.py parse --backend llm "客廳冷氣降低兩度"
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

OPS = {
    "light": {"turn_on", "turn_off", "set_brightness", "adjust_brightness"},
    "climate": {"turn_on", "turn_off", "set_temperature", "adjust_temperature"},
    "fan": {"turn_on", "turn_off", "set_percentage"},
    "cover": {"open", "close", "set_position"},
    "lock": {"lock", "unlock"},
    "switch": {"turn_on", "turn_off"},
}
NEEDS_VALUE = {"set_brightness", "adjust_brightness", "set_temperature",
               "adjust_temperature", "set_percentage", "set_position"}

SCHEMA = {
    "type": "object",
    "properties": {
        "actions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "entity_id": {"type": "string"},
                    "op": {"type": "string", "enum": sorted({o for s in OPS.values() for o in s})},
                    "value": {"type": "number"},
                },
                "required": ["entity_id", "op"],
            },
        },
        "clarify": {"type": "string"},
        "reject": {"type": "string"},
    },
    "required": ["actions"],
}


def load_home(path=None):
    with open(path or os.path.join(HERE, "home.json"), encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- validator
def validate(home, proposal):
    """Return dict(actions=[...resolved...], errors=[...], confirm=bool,
    clarify=str|None). Relative ops are resolved against current state."""
    ents = {e["entity_id"]: e for e in home["entities"]}
    state = home.get("state", {})
    out, errors, confirm = [], [], False
    if not isinstance(proposal, dict) or not isinstance(proposal.get("actions", []), list):
        return {"actions": [], "errors": ["bad schema"], "confirm": False, "clarify": None}
    for a in proposal.get("actions", []):
        eid, op, val = a.get("entity_id"), a.get("op"), a.get("value")
        e = ents.get(eid)
        if e is None:
            errors.append(f"unknown entity {eid}")
            continue
        if not e.get("allowed", False):
            errors.append(f"entity not allowed {eid}")
            continue
        if op not in OPS.get(e["domain"], ()):
            errors.append(f"op {op} unsupported for {eid}")
            continue
        if op in NEEDS_VALUE:
            if not isinstance(val, (int, float)):
                errors.append(f"missing value for {eid} {op}")
                continue
        st = state.get(eid, {})
        if op == "adjust_brightness":
            cur = st.get("brightness_pct", 0 if st.get("state") == "off" else 100)
            op, val = "set_brightness", max(1, min(100, cur + val))
        if op == "adjust_temperature":
            op, val = "set_temperature", st.get("temperature", 26) + val
        if op == "set_temperature":
            lo, hi = e.get("min_temp", 16), e.get("max_temp", 30)
            if not lo <= val <= hi:
                errors.append(f"temperature {val} out of range {lo}-{hi}")
                continue
        if op in ("set_brightness", "set_percentage", "set_position") and not 0 <= val <= 100:
            errors.append(f"{op} {val} out of range")
            continue
        # drop no-ops so 'turn off all lights' compares on effective changes
        s = st.get("state")
        if (op == "turn_off" and s == "off") or (op == "turn_on" and s not in (None, "off")) \
                or (op == "lock" and s == "locked") or (op == "unlock" and s == "unlocked") \
                or (op == "open" and s == "open") or (op == "close" and s == "closed"):
            continue
        if e.get("confirm") and op in ("unlock", "open"):
            confirm = True
        item = [eid, op] + ([round(float(val), 1)] if op in NEEDS_VALUE else [])
        if item not in out:
            out.append(item)
    return {"actions": out, "errors": errors, "confirm": confirm,
            "clarify": proposal.get("clarify") or None, "reject": proposal.get("reject") or None}


# ---------------------------------------------------------------- LLM backend
def registry_text(home):
    area_name = {k: v[0] for k, v in home["areas"].items()}
    lines = []
    for e in home["entities"]:
        st = home.get("state", {}).get(e["entity_id"], {})
        extra = ",".join(f"{k}={v}" for k, v in st.items())
        lines.append(f'{e["entity_id"]} | {e["name"]} | 別名:{"、".join(e["aliases"]) or "-"} | '
                     f'區域:{area_name.get(e["area"], "-")} | 可用操作:{",".join(sorted(OPS[e["domain"]]))} | 狀態:{extra}')
    return "\n".join(lines)


SYSTEM = """你是智慧家庭的指令解析器，只負責把使用者的臺灣中文口語指令轉成 JSON，不聊天。
規則：
1. 只能使用下方設備清單中的 entity_id，不可自行編造。
2. 一句話可以有多個動作，全部列在 actions。
3. 相對調整用 adjust_*：「亮一點」value=+20，「暗一點」value=-20，「降低兩度」value=-2，「高一度」value=1。
4. 「百分之三十」= 30；「二六」= 26；溫度單位是攝氏。
5. 「某區域的燈」指該區域所有燈；「其他燈都關掉」要列出每一盞。
6. 目標設備不明確（例如有兩台冷氣又沒有線索）或缺少必要數值時，actions 留空並在 clarify 用一句話詢問。
7. 設備不存在、不是家電控制或閒聊時，actions 留空並在 reject 說明原因。
8. ASR 可能有同音錯字（例如「客聽」=客廳、「床投燈」=床頭燈、「杜」=度），請依設備清單修正。

設備清單（entity_id | 名稱 | 別名 | 區域 | 可用操作 | 目前狀態）：
"""


def strict_schema(home):
    """SCHEMA with entity_id limited to the registry (grammar-enforced)."""
    s = json.loads(json.dumps(SCHEMA))
    s["properties"]["actions"]["items"]["properties"]["entity_id"]["enum"] = [e["entity_id"] for e in home["entities"]]
    s["properties"]["actions"]["items"]["additionalProperties"] = False
    s["additionalProperties"] = False
    return s


# Few-shot examples deliberately use phrasings that are NOT in tests*.jsonl.
FEWSHOT = [
    ("把臥室窗簾關到一半", {"actions": [{"entity_id": "cover.bedroom_curtain", "op": "set_position", "value": 50}]}),
    ("客廳主燈亮一點，電扇開到 40%", {"actions": [{"entity_id": "light.living_main", "op": "adjust_brightness", "value": 20},
                                          {"entity_id": "fan.living", "op": "set_percentage", "value": 40}]}),
    ("臥室冷氣調低 3 度", {"actions": [{"entity_id": "climate.bedroom_ac", "op": "adjust_temperature", "value": -3}]}),
    ("冷氣開", {"actions": [], "clarify": "請問是客廳冷氣還是臥室冷氣？"}),
    ("打開車庫門", {"actions": [], "reject": "沒有車庫門這個設備"}),
]


def number_hint(text):
    """Numbers are extracted by code, not by the model (night-1 finding)."""
    from nlu_rules import cn_num
    nums = re.findall(r"\d+(?:\.\d+)?\s*(?:%|度)?", cn_num(text))
    return f"（程式抽出的數字：{'、'.join(n.replace(' ', '') for n in nums)}）" if nums else ""


def llm_parse(home, text, url, n_predict=256, strict=False):
    msgs = [{"role": "system", "content": SYSTEM + registry_text(home)}]
    if strict:
        for q, a in FEWSHOT:
            msgs += [{"role": "user", "content": q}, {"role": "assistant", "content": json.dumps(a, ensure_ascii=False)}]
        text = text + number_hint(text)
    msgs.append({"role": "user", "content": text})
    body = {
        "messages": msgs,
        "temperature": 0,
        "max_tokens": n_predict,
        "response_format": {"type": "json_object", "schema": strict_schema(home) if strict else SCHEMA},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=300) as r:
        resp = json.load(r)
    dt = time.time() - t0
    content = resp["choices"][0]["message"]["content"]
    content = re.sub(r"<think>.*?</think>", "", content, flags=re.S).strip()
    try:
        prop = json.loads(content)
    except json.JSONDecodeError:
        prop = {"actions": [], "reject": "unparseable: " + content[:80]}
    return prop, dt, resp.get("timings", {})


# ---------------------------------------------------------------- scoring
def score(home, case, res):
    """Return (ok, reason)."""
    got = res["actions"]
    if case.get("expect_reject"):
        return (not got, "reject expected")
    if case.get("expect_clarify"):
        return (not got and bool(res["clarify"]), "clarify expected")
    exp = validate(home, {"actions": [dict(entity_id=e[0], op=e[1], **({"value": e[2]} if len(e) > 2 else {}))
                                      for e in case["expect"]]})["actions"]
    if not got and res["clarify"] and case.get("accept_clarify"):
        return (True, "clarify accepted")
    if not exp and case["expect"]:  # expected action is a no-op in the mock state:
        # still require that the parser understood it (no clarify / reject)
        ok = not got and not res["clarify"] and not res["reject"]
        return (ok, "no-op understood" if ok else "no-op but clarified/rejected")
    extra = set(case.get("accept_extra_entities", []))
    g = sorted(x for x in got if x[0] not in extra or x in exp)
    if sorted(exp) == g:
        if case.get("expect_confirm") and not res["confirm"]:
            return (False, "missing confirm")
        return (True, "match")
    for alt in case.get("alt", []):
        a = validate(home, {"actions": [dict(entity_id=e[0], op=e[1], **({"value": e[2]} if len(e) > 2 else {}))
                                        for e in alt]})["actions"]
        if sorted(a) == g:
            return (True, "alt match")
    return (False, f"expected {sorted(exp)}")


def skill_parse(skill, home, text, url, n_predict=256):
    msgs, ids = skill.messages(text, number_hint(text))
    schema = strict_schema(home)
    schema["properties"]["actions"]["items"]["properties"]["entity_id"]["enum"] = ids
    body = {"messages": msgs, "temperature": 0, "max_tokens": n_predict,
            "response_format": {"type": "json_object", "schema": schema},
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=300) as r:
        resp = json.load(r)
    content = re.sub(r"<think>.*?</think>", "", resp["choices"][0]["message"]["content"], flags=re.S).strip()
    try:
        prop = json.loads(content)
    except json.JSONDecodeError:
        prop = {"actions": [], "reject": "unparseable: " + content[:80]}
    return prop, time.time() - t0, resp.get("timings", {})


def make_backend(name, home, url):
    """Return parse(text) -> (proposal, seconds, timings)."""
    if name in ("llm-skill", "llm-skill-long"):
        from nlu_skill import Skill
        sk = Skill(home, mode="long" if name.endswith("long") else "short")
        return lambda t: skill_parse(sk, home, t, url)
    if name in ("slots", "rules+slots", "agree", "slots-c", "rules+slots-c"):
        from nlu_slots import SlotParser
        from nlu_rules import RuleParser
        sp, rp = SlotParser(home, url, compact=name.endswith("-c")), RuleParser(home)
        name = name.removesuffix("-c")

        def run_slots(t):
            if name == "slots":
                return sp.parse(t)
            t0 = time.time()
            r = rp.parse(t)
            if name == "rules+slots" and r.get("_conf") == "high":
                return r, time.time() - t0, {}
            s, _, tm = sp.parse(t)
            if name == "rules+slots" or r.get("_conf") == "low":
                return s, time.time() - t0, tm
            # agree: execute only when both parsers resolve to the same actions
            vr, vs = validate(home, r)["actions"], validate(home, s)["actions"]
            if sorted(vr) == sorted(vs):
                return (r if r.get("actions") or not s.get("actions") else s), time.time() - t0, tm
            if not vr and not vs:  # both decline: keep the rules' clarify/reject wording
                return r, time.time() - t0, tm
            return {"actions": [], "clarify": "我不太確定，可以換個說法再說一次嗎？", "_disagree": [vr, vs]}, time.time() - t0, tm
        return run_slots
    if name in ("llm", "llm-strict"):
        return lambda t: llm_parse(home, t, url, strict=name == "llm-strict")
    if name == "hassil":
        from nlu_hassil import HassilParser
        p = HassilParser(home)
    else:
        from nlu_rules import RuleParser
        p = RuleParser(home)

    def run(t):
        t0 = time.time()
        prop = p.parse(t)
        if name == "hybrid" and prop.get("_conf") == "low":
            prop2, dt, tm = llm_parse(home, t, url, strict=True)
            prop2["_via"] = "llm"
            return prop2, time.time() - t0, tm
        return prop, time.time() - t0, {}
    return run


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["eval", "parse"])
    ap.add_argument("text", nargs="?")
    ap.add_argument("--backend", default="llm", choices=["llm", "llm-strict", "llm-skill", "llm-skill-long", "slots", "rules+slots", "agree", "slots-c", "rules+slots-c",
                             "rules", "hybrid", "hassil"])
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--tests", default=os.path.join(HERE, "tests.jsonl"))
    ap.add_argument("--out")
    args = ap.parse_args()
    home = load_home()
    parse = make_backend(args.backend, home, args.url)
    if args.cmd == "parse":
        prop, dt, tm = parse(args.text)
        print(json.dumps({"proposal": prop, "validated": validate(home, prop), "sec": round(dt, 2), "timings": tm},
                         ensure_ascii=False, indent=1))
        return
    cases = []
    for path in args.tests.split(","):
        cases += [dict(json.loads(l), _set=os.path.basename(path)) for l in open(path, encoding="utf-8") if l.strip()]
    rows, ok_n, lat = [], 0, []
    for c in cases:
        prop, dt, tm = parse(c["text"])
        res = validate(home, prop)
        ok, why = score(home, c, res)
        ok_n += ok
        lat.append(dt)
        rows.append({"id": c["id"], "set": c.get("_set"), "cat": c["cat"], "text": c["text"], "ok": ok, "why": why, "sec": round(dt, 2),
                     "proposal": prop, "validated": res, "prompt_ms": tm.get("prompt_ms"), "predicted_ms": tm.get("predicted_ms")})
        print(f'{c["id"]:>2} {"OK " if ok else "BAD"} {dt:5.2f}s {c["cat"]:<13} {c["text"]}  -> {res["actions"]} '
              f'{"clarify:" + res["clarify"] if res["clarify"] else ""}{" errors:" + str(res["errors"]) if res["errors"] else ""}',
              flush=True)
    lat.sort()
    # executed-but-wrong: the dangerous failure (something happens that the user did not ask for)
    harm = sum(1 for r in rows if not r["ok"] and r["validated"]["actions"])
    print(f"\nACCURACY {ok_n}/{len(cases)} = {ok_n / len(cases):.1%}  wrong_executed {harm}  "
          f"latency median {lat[len(lat) // 2]:.2f}s  p90 {lat[int(len(lat) * .9)]:.2f}s")
    for sname in sorted({r["set"] for r in rows}):
        rs = [r for r in rows if r["set"] == sname]
        print(f"  SET {sname}: {sum(r['ok'] for r in rs)}/{len(rs)} wrong_executed "
              f"{sum(1 for r in rs if not r['ok'] and r['validated']['actions'])}")
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
