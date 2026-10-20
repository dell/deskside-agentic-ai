# Data manifest — 2026-10-19 @ dbb74c8

| File | What | Status / provenance |
|------|------|---------------------|
| `gb300_lightning_ladders_imported.json` | GB300 + Nemotron 3.5 Lightning concurrency ladders, shapes 200/200 and 6400/100 (C=1…1024) | **measured-imported** from a generated sweep-plot page (2026-10-13); source sha256 and mtime recorded in the JSON. Raw aiperf exports live on the measured node, not here. Produced by `tests/data/import_plot_ladder.py`. |
| `sizing.yaml` | Every capacity/performance number quoted in the docs, with status and source locations | consolidated 2026-10-19, refreshed 2026-10-20; `tests/test_consistency.py` verifies each `doc_refs` string still appears in the cited file |

## Ladders in sibling run directories

* `../20261019_295d430/` — GB10 + Lightning served through the Landscape fleet payload:
  chat 200/200 (C 1–16) and agent 60k/1k (C 1–4) quick ladders.
* `../20261019_422dbe6/` — Lightning on a Precision T6 tower with one RTX PRO 6000
  (GPU 4): chat 200/200, C=1–64. First run through the recipe contract wrapper —
  READY in 178 s, paired health script 0 FAIL including tool-call, monitoring
  scraped the endpoint.
* `../20261019_776d08c/` — Super VL on the same tower, TP=2 across two GPUs,
  chat 200/200 ladder.
* `../20261019_27689d3/` — Super VL agent 60k/1k + chat: one TP=2 instance and
  two TP=2 replicas behind the LiteLLM router.
* `../20261020_bb8ae93/` — GB300 + Lightning agent 60k/1k, C=1–64, through the
  recipe: the raw ladder behind `gb300.lightning.agent_c20` and
  `gb300.lightning.agent_ladder_remeasured`.

## Not here

* Earlier launch-era sweeps whose raw exports were not archived. The
  2026-10-20 re-measurement (`../20261020_bb8ae93/`) is the in-repo raw ladder
  for that shape under the `per_session = aggregate / C` convention. To
  regenerate: run the GB300 recipe, then `tests/aiperf/sweep.sh` against its
  endpoint.
