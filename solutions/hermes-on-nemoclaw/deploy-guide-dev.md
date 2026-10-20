# Hermes on NemoClaw — Developer Quick-Start

> **Who this is for:** developers and data scientists standing up the [Hermes](https://hermes-agent.nousresearch.com/)
> deskside agent on Dell Pro Precision with GB10/GB300 or Dell Pro Precision 9 tower workstations with NVIDIA
> GPUs.
>
> **IT fleet path:** [IT-Admin Guide](it-admin-guide.md).

Deploy the Hermes agent harness on Dell deskside hardware: **Hermes** (via the
[NemoClaw](https://github.com/NVIDIA/NemoClaw) runtime / `nemohermes`) on the [OpenShell](https://github.com/NVIDIA/OpenShell) sandbox plane, backed by a
local model on [vLLM](https://github.com/vllm-project/vllm). No cloud dependency for inference.

**Default model:** `nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4`
(served as `nvidia/nemotron-3.5-lightning`).

## Two-plane deployment

| Plane | What runs | How you install |
|-------|-----------|-----------------|
| **1 — Inference + observability** | vLLM (Nemotron) + [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) | recipe script from [`recipes/`](../../recipes/) (starts the shared tokenomics Prometheus + Grafana) |
| **2 — Agent** | NemoClaw installer → OpenShell + Hermes sandbox | `curl -fsSL https://www.nvidia.com/nemoclaw.sh \| bash` then `nemohermes` (scripted for fleets by `scripts/landscape/deploy-solution.sh`) |

```
   User / IDE / CLI
          │
   Hermes Agent (NemoClaw)  ─┐
          │                  │  Plane 2
   NemoClaw policy + sandbox ┤  ~/.nemoclaw + OpenShell (k3s)
   OpenShell gateway  ───────┘
          │  inference → local-vllm
          ▼
   vLLM /v1  + Prometheus / Grafana   ← Plane 1
```

## Prerequisites

- Ubuntu 24.04 LTS or newer on Dell Pro Precision 9 towers and Dell Pro Precision with GB300; GB10 systems ship with DGX OS.
- Docker CE + NVIDIA Container Toolkit installed and working
  (`docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu24.04 nvidia-smi`
  should succeed).
- A [Hugging Face](https://huggingface.co/) token (`HF_TOKEN`) with access to the [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4)
  NVFP4 model, **or** the model weights pre-cached in `~/.cache/huggingface`.
- Roughly 30 GB of free disk for the model + container images.

## Quick start

### 1) Plane 1 — local LLM

Pick the recipe matching your hardware:

| Dell system | Recipe |
|-------------|--------|
| Dell Pro Precision with GB10 | [`recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh`](../../recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh) |
| Dell Pro Precision 9 T2 / T4 / T6 (1× / 2× / 5× RTX PRO 6000) | [`recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh`](../../recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh) |
| Dell Pro Precision with GB300 | [`recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh`](../../recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh) |

Serve on port 8000:

_Commands in this guide run from the repository root (`git clone` this repo and `cd` into it)._

```bash
recipes/<platform>/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
curl -s http://localhost:8000/v1/models
```

Prefer `--gpu-memory-utilization 0.70` to leave headroom for agent workloads.
The recipe bakes the validated tool-call / reasoning parser flags for the
default model — see [Model recommendation](README.md#model-recommendation).

### 2) Plane 2 — NemoClaw + Hermes

Agent plane: use the NVIDIA installer (for a fleet, `scripts/landscape/deploy-solution.sh` runs it non-interactively across a fleet):

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
export PATH="$HOME/.local/bin:$PATH"
source "$HOME/.nvm/nvm.sh" && nvm use --lts

# Onboard the runtime. Choose Hermes / nemohermes when the wizard offers
# an agent type.
nemoclaw onboard

# Verify Hermes is registered:
nemohermes agents list        # expect: openclaw | hermes | ...

# Wire inference to Plane 1:
openshell provider create \
  --name vllm-local \
  --type openai \
  --credential OPENAI_API_KEY=local \
  --config base_url=http://host.docker.internal:8000/v1

openshell inference set --provider vllm-local --model nvidia/nemotron-3.5-lightning
openshell status              # Connected
nemohermes <sandbox> status   # Ready + Hermes Agent version
```

### 3) Smoke test

Two tests confirm the end-to-end path works:

```bash
# Tool execution (no LLM) — should print your kernel name
nemohermes <sandbox> exec -- uname -s

# Oneshot LLM inference through the agent path
hermes -z "Reply with exactly: HERMES_Z_OK"
```

If the LLM smoke returns overflow errors on the sandbox path, set
`model.max_tokens: 4096` in the sandbox Hermes config — the default max output
can exceed the model's context window on some configurations.

## Sizing pointer

Measured with the shipping-default model, same tool-using workload across all
systems (task success 100 % at every concurrency level tested):

| Measured system | Concurrent Hermes agents (measured guidance) |
|-----------------|----------------------------------------------|
| Dell Pro Precision with GB10 | 1 – 2 interactive (4 pass; wall-time grows ~11 s → ~23 s from c=1 to c=4). |
| Dell Pro Precision 9 T2 · 1× RTX PRO 6000 | 1 – 4; lowest wall-time measured (~3 – 4 s p50). |
| Dell Pro Precision 9 T4 · 2× RTX PRO 6000 | 1 – 4; clean scaling with tool-heavy workloads. |
| Dell Pro Precision 9 T6 · 5× RTX PRO 6000 (1 GPU active) | 1 – 4 per GPU; run one vLLM instance per GPU behind a small router. |
| Dell Pro Precision with GB300 | 1 – 4+; wall-time essentially flat across concurrency (~8 s p50). |

Full percentile detail: [README — Benchmarks & performance](README.md#benchmarks-performance-validation).

## Troubleshooting

- **vLLM `/v1/models` returns 404 or empty** — the server is still loading
  weights. Wait for `docker logs <container>` to show
  `Application startup complete.` (roughly 1–3 minutes on cached weights).
- **NemoClaw installer fails on Node.js version** — ensure `nvm` is loaded
  (`source "$HOME/.nvm/nvm.sh"`) and Node.js LTS is active.
- **`nemohermes exec` hits sandbox network policy** — the OpenShell sandbox
  enforces landlock plus L7 network policy. For tool-using agents that need
  to reach the local Plane 1 endpoint, configure the sandbox provider with
  `host.docker.internal:8000` rather than `127.0.0.1:8000`.

## Related

- [README](README.md) — solution overview, sizing, model lineup.
- [IT-Admin Guide](it-admin-guide.md) — fleet install and monitoring.
- [OpenClaw on NemoClaw](../openclaw-on-nemoclaw/) — the same runtime with the default OpenClaw agent, no
  agent.
- [Deployment Recipes](../../recipes/README.md) — serving recipe catalog.
