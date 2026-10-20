# tests/ — traceability for every number in the docs

Everything that backs (or checks) a capacity/performance claim lives here, **date- and commit-coded**
(`tests/data/<YYYYMMDD>_<gitsha>/`, `tests/data/latest` → newest).

```
tests/
  aiperf/shapes.yaml        workload shapes + concurrency ladders (chat 200/200, RAG 6400/100, long-gen 7000/1000, agent 60k/1k)
  aiperf/sweep.sh           run a ladder against a recipe's endpoint -> MANIFEST.json, commands.txt, raw exports, ladder.json
  aiperf/summarize.py       aiperf exports -> ladder.json (per_session = aggregate / C)
  data/<date>_<sha>/        MANIFEST.md, sizing.yaml (the machine-readable fact record), imported measured ladders
  data/import_plot_ladder.py      import a measured ladder from a generated sweep-plot page
  lib/mock_vllm.py          GPU-free OpenAI/vLLM-shaped mock for contract tests
  test_consistency.py       pytest: sizing.yaml traceability, recipes, monitoring, headless NemoClaw, client limits
  test_recipe_contract.sh   docker test of the readiness contract + monitoring wiring (mock server; any host)
```

Run: `python3 -m pytest tests/test_consistency.py -q` and `tests/test_recipe_contract.sh` (needs Docker and any image with python3; `MOCK_IMAGE=` to override).

## Methodology — measurement

Ladders run against the live recipe endpoints with
[AIPerf](https://github.com/ai-dynamo/aiperf): `sweep.sh` issues ≥40 synthetic requests per
level at concurrency *C* and records aggregate and per-session output tok/s under the
`per_session = aggregate / C` convention. Capacity tables cite the *C* at which per-session
throughput holds an explicit floor — **20 tok/s per session** in the Dell tables, with
10 tok/s as a looser secondary reference — for the shapes in `aiperf/shapes.yaml`.
Turning concurrent sessions into seats is a team-shape planning judgement (desk coverage,
utilisation, sessions per person); published pages stop at the measured sessions.

## Status of the evidence (read before quoting numbers)
| Item | Status |
|------|--------|
| GB300 Lightning agent ladder, re-measured 2026-10-20 | **measured-imported** (`20261020_bb8ae93/`) — ≥20 tok/s per session to about C=17 |
| GB300 Lightning chat/RAG ladders | **measured-imported** (`gb300_lightning_ladders_imported.json`) |
| GB300 Lightning agent @ c20 (~335 tok/s) | **measured-imported** (`20261020_bb8ae93/…/ladder.json`) |
| GB10 Lightning agent @ c20 (~66 tok/s) | `doc-reported` — launch-era figure; the in-repo GB10 agent ladder is a quick C 1–4 sweep |
| Single-stream spot checks (~310, ~111, 62–65 tok/s) | `spot-check` |
| `aiperf` flags in `sweep.sh` | exercised with aiperf 0.7.0 on the Precision towers (chat 200/200, C=1–64) |
| Precision T6 tower, one-GPU Lightning chat ladder | **measured-imported** (`20261019_422dbe6/t6-gpu4_…/ladder.json`) |

## Re-running the headline benchmark
1. Stop any other serving workload on the target GB300.
2. `recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` (blocks until ready).
3. `tests/aiperf/sweep.sh --url http://localhost:8000 --model nvidia/nemotron-3.5-lightning --tokenizer nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 --shape agent_60k_1k --ladder agent --container <container> --platform gb300`
4. Read the ladder back: per-session = aggregate / C; note the *C* where per-session falls
   below 20 (then 10) tok/s — that is the usable concurrency at each floor.
5. Update `sizing.yaml`, commit the data folder.

## Re-measure result (GB300, Lightning, agent shape, 2026-10-20)

Single instance, 60k-token prompts, 40 requests per level: 20 tok/s per session holds up to
about 17 concurrent sessions; 10 tok/s up to about 33. Raw ladder:
`tests/data/20261020_bb8ae93/`.
