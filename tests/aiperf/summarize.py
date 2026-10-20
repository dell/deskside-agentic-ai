#!/usr/bin/env python3
"""Collapse the per-level aiperf exports under <dir>/levelC*/ into <dir>/ladder.json
(per_session = aggregate / C)."""
import glob, json, os, re, sys
d = sys.argv[1]
man = json.load(open(os.path.join(d, "MANIFEST.json")))
def dig(o, *path):
    for k in path:
        if not isinstance(o, dict) or k not in o: return None
        o = o[k]
    return o
def metric(j, name):  # aiperf exports differ by version: top-level or under "result"
    for root in (j, j.get("result", {})):
        v = dig(root, name, "avg")
        if v is not None: return v
    return None
pts = []
for lvl in sorted(glob.glob(os.path.join(d, "levelC*")), key=lambda p: int(re.search(r"C(\d+)$", p).group(1))):
    c = int(re.search(r"C(\d+)$", lvl).group(1))
    files = [f for f in glob.glob(os.path.join(lvl, "**", "*.json"), recursive=True) if "profile" in os.path.basename(f) or "aiperf" in os.path.basename(f)]
    for f in files:
        j = json.load(open(f)); agg = metric(j, "output_token_throughput")
        if agg is None: continue
        pts.append({"c": c, "aggregate_tok_s": agg, "per_session_tok_s": agg / c,
                    "ttft_ms_avg": metric(j, "time_to_first_token"), "itl_ms_avg": metric(j, "inter_token_latency"),
                    "request_throughput": metric(j, "request_throughput"), "source": os.path.relpath(f, d)})
        break
out = {"manifest": "MANIFEST.json", "ladders": {man["shape"]: {"platform": man["platform"], "model": man["model"],
       "isl": man["isl"], "osl": man["osl"], "points": pts}}}
json.dump(out, open(os.path.join(d, "ladder.json"), "w"), indent=1)
print("ladder.json:", [(p["c"], round(p["aggregate_tok_s"], 1)) for p in pts])
