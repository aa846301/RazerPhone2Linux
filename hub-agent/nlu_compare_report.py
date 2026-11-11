#!/usr/bin/env python3
"""Summarize /tmp/cmp-<backend>-<set>.json written by nlu_compare.sh: LLM latency and every failure."""
import json
import statistics
import sys

SETS = ["tests", "tests-holdout", "tests-user", "tests-web"]
for b in sys.argv[1:] or ["rules+rewrite", "rules+slots-c"]:
    rs = []
    for t in SETS:
        d = json.load(open(f"/tmp/cmp-{b}-{t}.json"))
        rs += d["results"] if isinstance(d, dict) and "results" in d else d
    llm = sorted(r["sec"] for r in rs if r.get("sec", 0) > 0.05)
    print(f"== {b}: {sum(r['ok'] for r in rs)}/{len(rs)} ok; LLM-routed {len(llm)}: median {statistics.median(llm):.2f}s "
          f"p90 {llm[int(len(llm) * .9)]:.2f}s max {llm[-1]:.2f}s")
    for r in rs:
        if not r["ok"]:
            p = r.get("proposal", {})
            print(f"   FAIL [{r['cat']}] {r['text']} | rewrite={p.get('_rewrite')} | "
                  f"got={r['validated']['actions']} clarify={r['validated'].get('clarify')} | {r['why']}")
