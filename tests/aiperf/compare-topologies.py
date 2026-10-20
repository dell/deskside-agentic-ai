#!/usr/bin/env python3
"""Pick TP vs DP (or any two topologies) from MEASURED ladders for one workload.

  compare-topologies.py A.ladder.json B.ladder.json --shape agent_60k_1k --floor 20 [--names TP2 DP2]

Decision rule (docs/topology.md): the topology with more usable sessions at the floor wins;
if within --tie-pct (default 5 %), prefer the one with fewer moving parts (the first argument
should be the simpler topology, normally the single TP instance). A ladder that never crosses
the floor is reported as 'exhausted' and cannot win a comparison it did not finish.
"""
import argparse, json, math, sys

def concurrency_at_floor(points, floor):
    """Largest C whose per-session tok/s >= floor, log-log interpolated between ladder points.
    points: [(C, per_session_tok_s)] with per_session = aggregate / C (convention in sizing.yaml)."""
    pts = sorted(points)
    if pts[0][1] < floor: return None
    for (c0, p0), (c1, p1) in zip(pts, pts[1:]):
        if p0 >= floor > p1:
            t = (math.log(floor) - math.log(p0)) / (math.log(p1) - math.log(p0))
            return math.exp(math.log(c0) + t * (math.log(c1) - math.log(c0)))
    return pts[-1][0]  # floor never crossed within the ladder (ladder too short)

def load(path, shape):
    d = json.load(open(path))["ladders"][shape]
    return [(p["c"], p["per_session_tok_s"]) for p in d["points"]], d.get("platform", "?")

def evaluate(pts, floor):
    c = concurrency_at_floor(pts, floor)
    if c is None: return {"C": None, "sessions": 0.0, "exhausted": False, "note": "below floor even at C=%s" % pts[0][0]}
    ex = c == sorted(pts)[-1][0] and sorted(pts)[-1][1] >= floor
    return {"C": round(c, 1), "sessions": round(c, 1), "exhausted": ex}

def main(argv=None):
    ap = argparse.ArgumentParser(); ap.add_argument("a"); ap.add_argument("b"); ap.add_argument("--shape", required=True)
    ap.add_argument("--floor", type=float, default=20); ap.add_argument("--names", nargs=2, default=["A", "B"])
    ap.add_argument("--tie-pct", type=float, default=5.0)
    a = ap.parse_args(argv)
    ra = evaluate(load(a.a, a.shape)[0], a.floor); rb = evaluate(load(a.b, a.shape)[0], a.floor)
    out = {"shape": a.shape, "floor": a.floor, a.names[0]: ra, a.names[1]: rb}
    if ra["exhausted"] or rb["exhausted"]:
        out["choice"] = None; out["why"] = "a ladder ended before crossing the floor: extend it (tests/aiperf/shapes.yaml 'extended') and re-run"
    else:
        hi, lo = (ra, rb) if ra["sessions"] >= rb["sessions"] else (rb, ra); hn = a.names[0] if hi is ra else a.names[1]
        if lo["sessions"] and (hi["sessions"] - lo["sessions"]) / lo["sessions"] * 100 <= a.tie_pct:
            out["choice"] = a.names[0]; out["why"] = "within %.0f%% tie band -> simpler topology (%s)" % (a.tie_pct, a.names[0])
        else:
            out["why"] = "%.1f vs %.1f usable sessions at %g tok/s/session" % (hi["sessions"], lo["sessions"], a.floor); out["choice"] = hn
    print(json.dumps(out, indent=1)); return 0

if __name__ == "__main__": sys.exit(main())
