#!/usr/bin/env python3
"""Collect every measured ladder under tests/data into docs/assets/measured.json (read by the Recipe Configuration panel).
usage: build_measured.py [--check]"""
import glob, json, os, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "docs/assets/measured.json")
PLAT = [  # manifest platform prefix -> (tier platform key, topology description)
    ("gb10", ("gb10", "1 instance on the GB10 (unified memory)")),
    ("gb300", ("gb300", "1 instance on the GB300")),
    ("t6-gpu01-tp2", ("t4", "1 instance, TP=2 on 2x RTX PRO 6000")),
    ("t6-gpu34-tp2", ("t4", "1 instance, TP=2 on 2x RTX PRO 6000")),
    ("t6-dp2xtp2", ("t6", "2 replicas x TP=2 behind LiteLLM (4 of 5 GPUs)")),
    ("t6-gpu4", ("t2", "1 instance on 1x RTX PRO 6000 (Max-Q)")),
]
MODEL = {"nemotron-3.5-super-vl": "nvidia/nemotron-3.5-super-vl", "nemotron-3.5-lightning": "nvidia/nemotron-3.5-lightning"}

def norm_model(m):
    m = m.lower().replace(" ", "-").split("/")[-1]
    for k, v in MODEL.items():
        if k in m: return v
    return m

entries = {}
for f in sorted(glob.glob(os.path.join(ROOT, "tests/data/2*/*/ladder.json"))):
    run = f.split("/tests/data/")[1].split("/")[0]
    for shape, l in json.load(open(f))["ladders"].items():
        hit = next((v for k, v in PLAT if l["platform"].startswith(k)), None)
        if not hit: continue
        pts = [{"c": p["c"], "agg": round(p["aggregate_tok_s"], 1), "per": round(p["per_session_tok_s"], 2),
                "ttft": round(p["ttft_ms_avg"]) if p.get("ttft_ms_avg") is not None else None} for p in l["points"]]
        entries[(hit[0], norm_model(l["model"]), shape)] = {"platform": hit[0], "model": norm_model(l["model"]), "shape": shape,
            "isl": l.get("isl"), "osl": l.get("osl"), "topology": hit[1], "run": run, "source": "measured", "points": pts}
imp = os.path.join(ROOT, "tests/data/20261019_dbb74c8/gb300_lightning_ladders_imported.json")
if os.path.exists(imp):
    d = json.load(open(imp))
    for key, shape in (("w200", "chat_200_200"), ("w6400", "rag_6400_100")):
        l = d["ladders"].get(key)
        if l and ("gb300", "nvidia/nemotron-3.5-lightning", shape) not in entries:
            entries[("gb300", "nvidia/nemotron-3.5-lightning", shape)] = {"platform": "gb300", "model": "nvidia/nemotron-3.5-lightning",
                "shape": shape, "isl": l["isl"], "osl": l["osl"], "topology": "1 instance on the GB300", "run": "20261019_dbb74c8 (imported)",
                "source": "imported", "points": [{"c": p["c"], "agg": round(p["aggregate_tok_s"], 1), "per": round(p["per_session_tok_s"], 2), "ttft": None} for p in l["points"]]}
out = json.dumps(sorted(entries.values(), key=lambda e: (e["platform"], e["model"], e["shape"])), indent=1) + "\n"
if "--check" in sys.argv:
    cur = open(OUT).read() if os.path.exists(OUT) else ""
    print("stale" if cur != out else "current"); sys.exit(0 if cur == out else 1)
open(OUT, "w").write(out); print(len(entries), "ladders ->", os.path.relpath(OUT, ROOT))
