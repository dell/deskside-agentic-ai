# Deployment Recipes

Self-contained, runnable shell scripts that serve a model behind an
OpenAI-compatible API on NVIDIA hardware. Recipes are the deployment layer for
the reference architectures and solution templates in this repo.

## Layout

```
recipes/<platform>/<server>/docker-<model-slug>.sh   # Docker recipe (vLLM or NIM)
recipes/<platform>/<server>/serve-<model-slug>.sh    # llama.cpp native recipe
```

Platforms: `gb10`, `precision`, `gb300` · Servers: `vllm`.

## Conventions

- `#!/usr/bin/env bash` + `set -euo pipefail`.
- `--port PORT` (or `-p`) CLI override, env-var fallback declared at top.
- `docker pull` then `docker run -d --restart unless-stopped` (pre-clean the old
  container with `docker rm -f`); print the verify curl at the end.
- GB10 (DGX Spark, aarch64): `--gpus all --ipc=host --ulimit memlock=-1
  --ulimit stack=67108864`, mount `~/.cache/huggingface`.

## Readiness contract, health checks, monitoring (all recipes)

Every `docker-*.sh` now **builds, monitors and waits** before returning (shared code:
[`lib/common.sh`](lib/common.sh), [`lib/monitoring.sh`](lib/monitoring.sh)):

1. pull image, replace the old container, `docker run -d --restart unless-stopped`;
2. start/refresh the shared **tokenomics Prometheus + Grafana** (see [`../monitoring/`](../monitoring/README.md));
3. **block until ready** — container running, `/health` 200, served name in `/v1/models`, and a tiny
   completion succeeds — then print one machine-readable line:

```
READY {"ready":true,"container":"lightning-3.5-gb10","port":8000,"base_url":"http://localhost:8000/v1",
       "served_name":"nvidia/nemotron-3.5-lightning","models":[...],"seconds_to_ready":212,
       "max_model_len":200000,"client_max_output_tokens":16384,"client_prompt_budget_tokens":182592,
       "prometheus":"http://127.0.0.1:9090","grafana":"http://127.0.0.1:3000/d/deskside-tokenomics"}
```

| Exit | Meaning |
|-----:|---------|
| 0 | ready |
| 1 | container died / crash-looping (last logs + known-cause hints are printed) |
| 2 | wait timeout (default 1800 s; `--wait-timeout SEC`) |
| 3 | usage error |

Common flags on every recipe: `--no-wait`, `--wait-timeout SEC`, `--no-monitoring`, `--dry-run`
(prints the exact `docker` commands, tokens redacted, changes nothing — also the safe way for an agent to
preview a rollout). Env equivalents: `DESKSIDE_WAIT`, `DESKSIDE_WAIT_TIMEOUT`, `DESKSIDE_MONITORING`, `DESKSIDE_DRY_RUN`.

**Per-recipe health assessment** (field debugging; read-only except one tiny completion): each recipe has a
sibling `health-<model>.sh` — host/driver/runtime/memory/disk → container (state, restarts, OOM, restart policy) →
endpoint (`/health`, `/v1/models`, smoke completion, optional `--tool-test` structured tool call) → load/KV-cache →
log-signature scan with fixes → monitoring. Exit 1 on any FAIL; `--json` for automation; `--bundle [DIR]` writes
a token-redacted debug tarball.

```bash
recipes/gb10/vllm/health-nemotron-3.5-lightning-nvfp4.sh --tool-test
recipes/precision/vllm/health-qwen3.8-flash-next-nvfp4.sh --json
recipes/lib/health.sh --container NAME --port PORT --served MODEL      # any vLLM container
recipes/lib/client-config.sh --port 8000 --served nvidia/nemotron-3.5-lightning   # window-aligned client configs
```

| Recipe | Health wrapper |
|--------|----------------|
| `gb10/…lightning` | `gb10/vllm/health-nemotron-3.5-lightning-nvfp4.sh` (+ unified-memory squatter check) |
| `gb10/…qwen3.8-27b` | `gb10/vllm/health-qwen3.8-27b-nvfp4.sh` |
| `precision/…lightning` | `precision/vllm/health-nemotron-3.5-lightning-nvfp4.sh` (+ TP / PCIe all-reduce check) |
| `precision/…flash-next` | `precision/vllm/health-qwen3.8-flash-next-nvfp4.sh` (+ ≥128 GB host-RAM check) |
| `gb300/…lightning` | `gb300/vllm/health-nemotron-3.5-lightning-nvfp4.sh` |
| `gb300/…glm-5.3-flash` | `gb300/vllm/health-glm-5.3-flash-nvfp4.sh` (+ arm64 image check) |

Container names, default ports and served names are unchanged (precision Lightning: `lightning-3.5-precision-<port>`;
that recipe now also re-derives the name when `--port` is given). Tested by `tests/test_recipe_contract.sh` (mock server,
ready/died/timeout/`--no-wait` paths) and `tests/test_consistency.py` (dry-run of all recipes); the health script was run
against live containers (Lightning and Super VL on T6, Super VL on GB300, [GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) on GB300).

## Models

Each model carries its size designation — where a solution designates it.
**Agentic** = the S/M/L designation in the Agentic Coding solution; further
solution columns get added as other templates designate models.

| Model | Quant | Agentic Coding | Recipes |
|-------|-------|----------------|---------|
| **[Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4) 30B-A3B** (`nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4`) | NVFP4 | **S — default** (measured fallback on M/L) | [`gb10`](gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh) · [`precision`](precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh) · [`gb300`](gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh) |
| **[Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4)** (`nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4`, ~62 GB) | NVFP4 | **M/L — default** | [`precision`](precision/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh) · [`gb300`](gb300/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh) |
| **[Qwen3.8-27B](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4)** (`nvidia/Qwen3.8-27B-NVFP4`) | NVFP4 (MTP head kept BF16) | **S — alternative** | [`gb10`](gb10/vllm/docker-qwen3.8-27b-nvfp4.sh) |
| **[Qwen3.8-Flash-Next](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4)** (`nvidia/Qwen3.8-Flash-Next-NVFP4`) | NVFP4 (MTP ×3 + engram CPU offload) | **M — alternative** | [`precision`](precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh) |
| **[GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4)** (`RedHatAI/GLM-5.3-Flash-NVFP4`) | NVFP4 | **L — alternative** | [`gb300`](gb300/vllm/docker-glm-5.3-flash-nvfp4.sh) |

There is **no Nemotron L-class designation right now** — 3.5 Super replaces
3 Ultra — so Super VL, the M/L default, also serves the L tier; Lightning
multi-instance / DP is the measured fallback and GLM-5.3-Flash is the L
alternative.

## Agentic Coding — model × platform

Support rule: **S-class models run on S/M/L hardware, M-class on M/L, L-class
on L.** Cells give quick perf numbers where measured (see notes); ✓ = in
designation range, no published number yet; — = outside the designation range.
Tests are run in-designation only.

| Platform (tier) | Lightning · S default | Qwen3.8-27B · S alt | Super VL · M default¹ | Flash-Next · M alt | GLM-5.3-Flash · L alt |
|-----------------|-----------------------|---------------------|------------------------|--------------------|-----------------------|
| **GB10** · S (128 GB unified) | ~66 out tok/s @ c20 (agent shape)² | ~62–65 out tok/s 1-stream (MTP)³ | — | — | — |
| **Precision T2** · S (96 GB) | 5,352 chat / 399 agent tok/s² | ✓ | — | — | — |
| **Precision T4** · M (192 GB) | ✓ | ✓ | 168 agent / 1,814 chat tok/s @ c32 / c64 (TP=2)⁴ | ✓ | — |
| **Precision T6** · L (480 GB) | ✓ | ✓ | 252 agent / 2,020 chat tok/s @ c32 / c64 (2 × TP=2)⁴ | ✓ | ✓ (recipe targets GB300) |
| **GB300** · L (252 GB HBM3e) | ~335 out tok/s @ c20; ≥20 tok/s/session to C≈17² | ✓ | 225 agent / 3,694 chat tok/s @ c32 / c64⁴ | ~310 out tok/s 1-stream (spot) | ~111 out tok/s 1-stream (spot) |

1. Super VL is the M/L default (flags from the model card plus multi-user settings from the Nemotron-3-Super recipes);
   measured results are in note 4; Lightning remains the S-tier default. No Nemotron L class exists beyond it
   (3.5 Super replaces 3 Ultra).
2. Aggregate output tok/s on the agent-workflow shape (ISL 60k / OSL 1k) at
   concurrency 20 unless annotated otherwise; "chat" cells are aggregate
   chat-sweep peaks; GB300 per-session concurrency from the re-measured agent
   ladder in the solution README. Routed (multi-instance) figures are taken behind a
   LiteLLM router with `--num_workers` matched to the host's core allocation;
   launch-era figures taken through a single-worker router (which capped the
   endpoint near 2.4k tok/s) are retired as measurement artifacts, so those
   cells carry no published number yet.
3. Measured with the predecessor `unsloth/` NVFP4 checkpoint on locked-clock
   GB10; the current `nvidia/` ModelOpt pin keeps the same architecture
   (MTP preserved).
4. Super VL, aiperf 0.7.0, 64 requests per level: agent = ISL 60k / OSL 1k aggregate output tok/s at concurrency 32; chat = ISL 200 / OSL 200 at concurrency 64 (the ladder ended before the chat peak). T4 numbers are one TP=2 instance on two RTX PRO 6000 Max-Q GPUs of a T6; T6 numbers are two TP=2 replicas behind LiteLLM on four of its five GPUs. Raw ladders: `tests/data/`.

## Recommended deployments

Exactly **one** recommended recipe per model × platform × use-case set,
chosen by best measured performance (ties broken by fewer moving parts).
Use-cases: **chat** = aggregate throughput at high concurrency (200-in /
200-out sweep); **agent** = agentic long-context shape (ISL 60k / OSL 1k)
at concurrency 20. Routed variants always run LiteLLM with
`--num_workers` matched to the host's core allocation.

| Model · Platform | Use-case | Recommended recipe | Topology | Measured |
|------------------|----------|--------------------|----------|----------|
| Lightning · GB10 | chat + agent | `gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` | 1 instance | ~66 tok/s agent-c20 |
| Qwen3.8-27B · GB10 | chat + agent | `gb10/vllm/docker-qwen3.8-27b-nvfp4.sh` | 1 instance (MTP) | 62–65 tok/s 1-stream |
| Lightning · T2 | chat + agent | `precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` | 1 instance | 5,352 chat / 399 agent tok/s |
| Lightning · T4 | chat + agent | `precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` | topology chosen per workload by measurement ([docs/topology.md](../docs/topology.md)); DP = `lib/launch-replicas.sh` (2×TP=1 + LiteLLM), TP = single instance | in designation (see matrix above) |
| Lightning · T6 | chat + agent | `precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` | topology chosen per workload by measurement ([docs/topology.md](../docs/topology.md)); DP = 5×TP=1 + LiteLLM, TP = TP=4 (snapped) | in designation (see matrix above) |
| Lightning · GB300 | chat + agent | `gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` | 1 instance | ~335 tok/s agent-c20 |
| Flash-Next · GB300 | chat | `precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh` | 1 instance (TP=1, pin `FLASHNEXT_GPUS` on shared hosts) | 310 tok/s 1-stream |
| Flash-Next · T4 | chat | `precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh` | TP=2 across the pair | in designation (see matrix above) |
| GLM-5.3-Flash · GB300 | chat | `gb300/vllm/docker-glm-5.3-flash-nvfp4.sh` | 1 instance (≤252 GB HBM3e) | 111 tok/s 1-stream |
| Qwen3.8-27B · T6 | chat | `gb10/vllm/docker-qwen3.8-27b-nvfp4.sh` | topology chosen per workload by measurement ([docs/topology.md](../docs/topology.md)); DP = 5×TP=1 + LiteLLM, TP = TP=4 (snapped) | in designation (see matrix above) |
| Qwen3.8-27B · GB300 | chat | `gb10/vllm/docker-qwen3.8-27b-nvfp4.sh` (`QWEN38_27B_GPUS=device=<index-or-UUID>`, `QWEN38_27B_DIR=<HF-cache snapshot>`) | 1 instance | in designation (see matrix above) |

Multi-instance topologies require the multi-GPU `*_GPUS` device pin
(`precision` recipes; `gb10` qwen recipe's `QWEN38_27B_GPUS`). TP > 1 on
PCIe RTX PRO towers needs `NEMOTRON_LIGHTNING_DISABLE_CUSTOM_AR=1` (see
the recipe headers).

Add new recipes and models here and keep these tables in sync.

## Sizing

Use the sizing rules in [S/M/L Sizing](../docs/sizing.md) to choose a
model + quant that fits the target platform's memory budget.
