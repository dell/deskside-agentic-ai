#!/usr/bin/env python3
"""Import a measured concurrency ladder from a generated sweep-plot page.

Sweep-plot pages embed `const SWEEP = {...}` produced from aiperf exports
(per-session = aggregate / C). This script extracts it verbatim and records
provenance (source file, sha256, mtime) so the numbers are traceable.
usage: import_plot_ladder.py <plot-page.html> <out.json>
"""
import hashlib, json, os, re, sys, time
src, out = sys.argv[1], sys.argv[2]
raw = open(src, encoding="utf-8").read()
m = re.search(r"const SWEEP = (\{.*?\});\s*const UC", raw, re.S)
sweep = json.loads(m.group(1))
uc = json.loads(re.search(r"const UC = (\{.*?\});", raw, re.S).group(1))
res = {"provenance": {"source": os.path.basename(src) + " (generated sweep-plot page on the measurement host)",
       "sha256": hashlib.sha256(raw.encode()).hexdigest(),
       "source_mtime": time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(src))),
       "note": "Extracted from the generated plot page; raw aiperf exports live on the measured node, not in this repo. per_session = aggregate / C."},
       "shapes": uc, "ladders": {}}
for shape, plats in sweep.items():
    for plat, d in plats.items():
        res["ladders"][shape] = {"platform": plat, "model": d["model"], "isl": uc[shape]["isl"], "osl": uc[shape]["osl"],
            "points": [{"c": c, "aggregate_tok_s": a, "per_session_tok_s": p} for c, a, p in d["series"]]}
json.dump(res, open(out, "w"), indent=1)
print("wrote", out, {k: len(v["points"]) for k, v in res["ladders"].items()})
