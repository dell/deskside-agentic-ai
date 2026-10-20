#!/usr/bin/env python3
"""Deterministic sizing-agent replay: can a sizing agent answer canonical
capacity questions from sizing.yaml, and with what confidence?
No LLM involved -- this scores the DATA, not a model.  Exit 0 always; prints a matrix."""
import os, sys, yaml
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
facts = {f["id"]: f for f in yaml.safe_load(open(os.path.join(ROOT, "tests/data/latest/sizing.yaml")))["facts"]}
Q = [
 ("How many concurrent agent sessions hold 20 tok/s on one GB300?", ["gb300.lightning.agent_ladder_remeasured"]),
 ("Sustained agent throughput on one GB10 with the shipped model?", ["gb10.lightning.agent_c20.aggregate_tok_s"]),
 ("Peak throughput of a T2 (Lightning)?", ["t2.lightning.tok_s"]),
 ("What does a T4 (M tier) deliver?", ["t4.t6.lightning", "m_l.super_vl"]),
 ("Is the M/L default model measured?", ["m_l.super_vl"]),
 ("GLM-5.3-Flash speed on GB300?", ["gb300.glm53_flash.single_stream"]),
 ("Hermes agents per GB10 / T2 / GB300?", ["agents.hermes_harness.wall_p50_s"]),
 ("GB300 Lightning chat ladder to C=1024?", ["gb300.lightning.chat_ladders"]),
]
ok = {"measured-imported": "ANSWER (measured)", "doc-reported": "ANSWER (doc-reported; raw missing)", "spot-check": "ANSWER (spot-check only)"}
print(f"{'question':62} {'verdict'}")
tally = {}
for q, ids in Q:
    sts = [facts[i]["status"] for i in ids]
    if all(s in ok for s in sts): v = ok[sts[0]]
    elif "pending" in sts: v = "CANNOT ANSWER: pending measurement"
    elif "retired-model" in sts: v = "CAVEAT: retired-model data only"
    else: v = "?"
    tally[v.split(":")[0].split(" (")[0]] = tally.get(v.split(":")[0].split(" (")[0], 0) + 1
    print(f"{q:62} {v}")
print(tally)
