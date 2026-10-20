# AGENTS.md — working guide for coding agents

This repository holds open **Solution Templates** for agentic AI on Dell deskside
systems powered by NVIDIA: Dell Pro Precision with GB10 (128 GB unified,
aarch64), Dell Pro Precision with GB300 (252 GB HBM3e, aarch64), and Dell Pro
Precision 9 towers (T2/T4/T6 with RTX PRO 6000 GPUs). Each template pairs a
use case with served models, recipes, measured performance, and operator
guides. It ships no NVIDIA runtime binaries — recipes pull and configure public
images at deployment time.

Read this file before editing. The conventions below are enforced by
`python3 -m pytest tests/` and the docs-site check; the CI-equivalent pre-flight is
always the same two commands:

```bash
python3 -m pytest tests/ -q              # data ↔ docs ↔ recipes consistency
python3 scripts/docs/regen.py --check    # published HTML matches Markdown sources
```

## Layout — what lives where

| Path | Purpose | Agent note |
|------|---------|------------|
| `solutions/<template>/` | One Solution Template each: `README.md` (overview + sizing tables), `it-admin-guide.md`, `deploy-guide-dev.md`, `landscape-fleet-deploy.md` | Markdown is the source; HTML pages are generated from it |
| `docs/` | Cross-cutting pages: `sizing.md` (fit rules, status vocabulary), `stack.md` (models + licenses), `topology.md` (TP vs DP, measured), `operations.md` (port map, co-tenancy, FAQ), `scope.md`, `glossary.md`, `stack-composition.md`, `personas.md` | Same: edit `.md`, never the `index.html` by hand |
| `recipes/{gb10,precision,gb300}/vllm/` | Executable serving recipes `docker-<model>.sh` + paired `health-<model>.sh` | The authoritative serving commands; docs quote them, not the reverse |
| `recipes/lib/` | Shared contract: `common.sh` (flags, ports, READY JSON), `health.sh`, `launch-replicas.sh` (DP replicas), `litellm.sh` (router), `monitoring.sh`, `client-config.sh` | Every recipe sources `common.sh`; change here → run the full suite |
| `recipes/versions.lock` | Image pins per model/arch; `ds_image()` resolves them | Pin policy: released tag → digest → nightly |
| `scripts/` | `landscape/` (fleet payloads + API client), `airgap/pack-images.sh`, `multicast/` (LAN mass-distribution), `nemoclaw/headless-install.sh`, `docs/regen.py` | Fleet/ops lanes referenced from the guides |
| `tests/data/<date>_<sha>/` | Raw measurement record per run (`ladder.json`, `MANIFEST.json`, `commands.txt`) + `latest/sizing.yaml` | See next section |
| `tests/aiperf/` | `sweep.sh`, `shapes.yaml`, `compare-topologies.py` | How to generate new numbers |
| `tests/test_consistency.py`, `test_recipe_contract.sh` | The enforcement suite | Run before every commit |
| `monitoring/` | Prometheus + Grafana tokenomics stack started by recipes; `alerts.yml` | Every recipe brings it up unless `DESKSIDE_MONITORING=0` |

## Sources of truth, in precedence order

1. **`recipes/`** — what to run. Flags, images, ports, GPU pinning.
2. **`tests/data/latest/sizing.yaml`** — every number quoted anywhere in this
   repo, with provenance (`status`, `data_file`, `doc_refs`). Published
   performance claims must exist here first.
3. **`recipes/versions.lock`** — what image runs.
4. **`solutions/**/*.md`, `docs/*.md`** — narrative and tables generated from
   the above.

`test_consistency.py` fails when doc text drifts from `sizing.yaml`
(`doc_refs` are checked verbatim) or when recipe behavior no longer matches the
documented tables. Change a number or its sentence → update both sides in the
same commit.

## Recipe contract (do not break for scriptability)

Every recipe, and the replica launcher, behaves identically:

- **Blocks until the endpoint serves**, then prints one machine-readable line:
  `READY {"ready":true,"container":…,"port":…,"base_url":…,"bind":…,"auth":…,"served_name":…,"models":[…],"seconds_to_ready":…,"max_model_len":…,"client_max_output_tokens":…,"client_prompt_budget_tokens":…,"prometheus":…,"grafana":…}`
  Parse that line — don't scrape logs or sleep-poll.
- **Meaningful exit codes** (0 = ready, nonzero = why not). Common flags:
  `--port`, `--dry-run` (prints the plan, touches nothing), `--help`.
- **Env overrides** follow `<RECIPE>_<VAR>` naming; global scheme vars are
  `DESKSIDE_BASE_PORT` (ports count up from one base, default 8000),
  `DESKSIDE_BIND_ADDR`, `DESKSIDE_API_KEY`, `DESKSIDE_IMAGE_CHANNEL`,
  `DESKSIDE_WAIT`, `DESKSIDE_MONITORING`, `DESKSIDE_DRY_RUN`.
- **Ports are per-container** (`ds_pick_port`); co-tenancy rules and the full
  port map live in [`docs/operations.md`](docs/operations.md).
- Images always resolve through `ds_image()` to a pin — never a bare `:latest`
  in committed code.
- `health-<model>.sh` wrappers re-check a running endpoint (exit-coded,
  `--json`, `--bundle`); use them instead of ad-hoc `curl` in new scripts.

## Working rules for edits

- **Markdown is the source of the docs site.** After any `.md` change, run
  `python3 scripts/docs/regen.py`; CI runs `--check`. Never edit
  `docs/**/index.html` directly.
- **Number discipline.** Quote published numbers only from measured facts.
  Where nothing is measured, label the figure a planning estimate and name its
  source cell. Never move a number across a model, quant, or topology boundary
  without a new sweep.
- **Naming and voice.** Dell-first: "Dell Pro Precision with GB300 (252 GB
  HBM3e, aarch64)", not "a GB300 system". Address readers as "you"; the words
  "customer" and vendor-sales filler do not appear. First mention of a model on
  a page links its Hugging Face card (see [`docs/stack.md`](docs/stack.md)).
- **No in-progress banners in published pages.** Unpublished capability and
  future work belongs on [`docs/scope.md`](docs/scope.md) or the backlog-style
  notes of a guide, phrased as what the design supports today.
- **Hygiene (pre-release scans reject these):** no internal hostnames,
  internal git URLs, private IP ranges, personal paths, or credentials
  anywhere in tracked files; raw aiperf `level*/` directories stay untracked —
  commit the `ladder.json` + `MANIFEST.json` + `commands.txt` record.
- **Commits:** imperative `area: summary` (`recipes:`, `docs:`, `tests:`,
  `higher-ed:` …); keep data + docs + code for one fact in a single commit.

## Task guide — sizing a deployment

1. Read [`docs/sizing.md`](docs/sizing.md): model-fit rule (NVFP4 ≈ 4.5
   bits/weight + KV + headroom; MoE counts total params) and the S/M/L tier
   definitions.
2. Pick the tier from the workload shape (concurrency, context, latency), then
   the tier's pinned default model; alternatives follow the support rule
   (S-class models run on S/M/L hardware, M-class on M/L, L-class on L) in
   [`recipes/README.md`](recipes/README.md).
3. Report capacity as usable concurrency: the *C* at which per-session output
   holds your floor (the templates' tables use 20 tok/s per session). Converting
   sessions to seats is a team-shape planning judgement — keep it in pilot
   planning, not in published pages.
4. Take capacity **from the measured cells** of `sizing.yaml` / the matrix in
   `recipes/README.md` and cite them. If the target shape is unmeasured, scale
   from the nearest measured cell, say so in the text, and drive measurement in
   the target environment with `tests/aiperf/sweep.sh`.
5. Remember TP vs DP is a per-workload, measured choice
   ([`docs/topology.md`](docs/topology.md)) — never a stylistic one.

## Task guide — deploying

- **Single host / pilot:** follow the solution's `deploy-guide-dev.md`; run the
  tier's recipe, parse the `READY` line, run the paired `health-<model>.sh`,
  then the guide's verification checklist. Monitoring comes up with the recipe.
- **Fleet / IT rollout:** the solution's `it-admin-guide.md` (prereqs, port
  map, co-tenancy, verification) and `landscape-fleet-deploy.md` for Canonical
  Landscape mass execution — payloads in `scripts/landscape/`
  (`stage-and-run.sh`, `deploy-serving-recipe.sh`, `deploy-solution.sh`,
  `verify-serving.sh`, seat reset, root-script disable after deployment).
  Every payload is idempotent and exit-coded so automation can trust them.
- **No internet:** `scripts/airgap/pack-images.sh` saves images + checksums on
  a connected host; the load procedure is in `docs/operations.md`.
- **Many seats, big assets:** `scripts/multicast/` distributes course images and
  model caches over LAN in one pass (higher-ed guide has the time model).
- **Alerting/telemetry:** `monitoring/alerts.yml` and the Tokenomics
  dashboards; do not invent metrics that DCGM/vLLM don't emit.

## Task guide — adapting a template to a new environment

Fixed (adopt as-is; they make scripts composable): the recipe contract,
`DESKSIDE_*` env scheme, port scheme, versions-locking, measurement workflow,
doc↔data sync.

Adaptable, with the knob that moves it:

| Concern | Knob | Verify with |
|---------|------|-------------|
| Private registry / proxy | per-recipe `*_IMAGE` env, `DESKSIDE_IMAGE_CHANNEL`; airgap pack | recipe `--dry-run`, then live `READY` |
| Model choice (license, language, quality) | support rule + fit rule; swap per `recipes/README.md`; keep required backend flags (Marlin NVFP4 pins, MTP) from the recipe header | `tests/aiperf/sweep.sh` in the new shape |
| Concurrency vs context (TP/DP/replicas) | `launch-replicas.sh` + `litellm.sh` topology; snap via `ds_snap_tp` | `compare-topologies.py` |
| Ports, bind, auth | `DESKSIDE_BASE_PORT`, `DESKSIDE_BIND_ADDR`, `DESKSIDE_API_KEY` | `health-<model>.sh`, alert rules |
| Model cache / disk layout | HF cache volume (`~/.cache/huggingface`, NAS-backed for shared pools; rsync-warm procedure in the coding IT guide) | first-token cold/hot timings in deploy guide |
| Windows seats, WSL, different orchestrator | documented as future scope; the Linux recipe contract is the portable part | — |
| Agent sandbox policy | sample policies in the OpenClaw/Hermes dev guides under NemoClaw/OpenShell | dev-guide verification steps |
| Seats lifecycle (lab resets, re-imaging) | higher-ed IT-admin guide + `scripts/landscape/reset-seat.sh` | timed reset drill |

Adaptation rules:

1. Start from the nearest **measured** configuration; document each deviation.
2. A changed model, quant, or topology **invalidates inherited numbers** —
   re-sweep and record a new `sizing.yaml` fact (with `data_file` provenance
   and `doc_refs` pointing at the text you write) before publishing capacity
   claims.
3. An adapted configuration is "good" at the promotion gates: clean
   `READY`, error rate ≤ 1 % through the full sweep, p99 within the use-case
   target, sustained tok/s on plan, across ≥ 2 consistent runs.
4. Ship the adaptation as a recipe variant when it will be re-run; ship it as
   guide text when it won't.

## Quick pointers

- Terms and required phrasing: [`docs/glossary.md`](docs/glossary.md)
- Ports, co-tenancy, secrets, FAQ: [`docs/operations.md`](docs/operations.md)
- Which engine for what: [`docs/stack.md`](docs/stack.md) (with licenses per model)
- Scope (future work, what we won't cover): [`docs/scope.md`](docs/scope.md)
- Measurement method + traceability: [`tests/README.md`](tests/README.md)
- Monitoring stack and alerts: [`monitoring/README.md`](monitoring/README.md)
