# OpenClaw on NemoClaw — IT-Admin Deployment Guide

Runbook for deploying and operating the [NemoClaw](https://github.com/NVIDIA/NemoClaw) runtime as the substrate for
a fleet's custom agents on Dell deskside systems.

**Target:** a new admin reaches a working, verified agent sandbox in
**< 60 minutes** (warm model cache) following this guide end-to-end.

> **Developer quick-start:** [Developer Deploy Guide](deploy-guide-dev.md).
>
> **Shipping agent:** if the fleet wants the ready-to-use [Hermes](https://hermes-agent.nousresearch.com/) agent, see
> [Hermes on NemoClaw](../hermes-on-nemoclaw/) (IT-Admin guide there).

## Overview

| Plane | Contents | Install path |
|-------|----------|--------------|
| **Prerequisites** | [Docker](https://www.docker.com/) CE + NVIDIA Container Toolkit + secrets + disk for weights | Ubuntu package install |
| **Plane 1 — Serving** | [vLLM](https://github.com/vllm-project/vllm) + Nemotron + [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) | Ansible playbook or the recipe scripts |
| **Plane 2 — Agent runtime** | NemoClaw + [OpenShell](https://github.com/NVIDIA/OpenShell) (k3s + policy engine + sandboxes) | NVIDIA installer, scripted for fleets by `scripts/landscape/deploy-solution.sh` |
| **Agent code** | Your custom agent(s) or the shipping Hermes agent | See the Hermes on NemoClaw solution for Hermes |

The **same Plane 1 endpoint** is reusable across other solutions in this
repository (coding assistant, Hermes agent, video search & summarization) —
you do not need one vLLM instance per solution on the same workstation.

## 0. Prerequisites

Every target host must have:

- **Ubuntu 24.04+** on Dell Pro Precision 9 towers and Dell Pro Precision with GB300; GB10 systems ship with **DGX OS**.
- **Docker CE ≥ 24** and **NVIDIA Container Toolkit** — verify with
  `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu24.04 nvidia-smi`.
- **[Hugging Face](https://huggingface.co/) token** (`HF_TOKEN`) with access to [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4)
  NVFP4, or weights already staged in `~/.cache/huggingface`.
- **~30 GB free** in the HF cache path (~60+ GB on L tier if serving larger
  alternative models).
- **Outbound network** to `huggingface.co`, `nvidia.com`, `github.com` from
  Plane 2 hosts for the initial NemoClaw installer. For air-gapped fleets,
  pre-seed `~/.cache/huggingface` from a connected host (`rsync`) and run the
  Plane 2 install once from staged media per NVIDIA's installer docs.

```bash
# Prerequisite checks — every command must pass
cat /etc/os-release | grep VERSION_ID            # 24.04+
nvidia-smi --query-gpu=driver_version --format=csv,noheader   # >= 570
docker --version                                 # Docker 24+
docker info 2>/dev/null | grep -i nvidia         # nvidia runtime present
df -h ~/.cache/huggingface --output=avail 2>/dev/null || df -h /home --output=avail
# Expected: >= 30 GB free (S/M)
_Commands in this guide run from the repository root (`git clone` this repo and `cd` into it)._

```

## 1. Plane 1 — Serving

### Path A — Multi-host fleet

Fleet rollout of the serving recipes today uses Canonical Landscape script
execution (no SSH) — see [Fleet Deploy via Landscape](../agentic-coding/landscape-fleet-deploy.md).
Until then map hosts to per-tier recipes in your own automation; every recipe
blocks until ready and exits non-zero on failure, so it composes safely.

### Path B — Recipe script per host

For a single workstation, run the platform recipe directly:

| Dell system | Recipe |
|-------------|--------|
| Dell Pro Precision with GB10 | `recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` |
| Precision T2 / T4 / T6 (Blackwell) | `recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` |
| Dell Pro Precision with GB300 | `recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` |

```bash
recipes/<platform>/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
curl -sf http://localhost:8000/health && echo VLLM_OK
```

On T6 (L tier), run one vLLM instance per GPU behind a [LiteLLM](https://www.litellm.ai/)-style proxy for
load balancing instead of tensor-parallelism over PCIe.

### Verify Plane 1

```bash
curl -sf  http://localhost:8000/health              # 200
curl -s   http://localhost:8000/v1/models           # lists nemotron-lightning
curl -sfI http://localhost:3000/login | head -1     # Grafana (port may differ: printed by the recipe)
curl -sf  http://localhost:9090/-/healthy           # Prometheus (port may differ: printed by the recipe)
```

## 2. Plane 2 — NemoClaw runtime

Plane 2 uses NVIDIA's shipping installer; for a fleet, `scripts/landscape/deploy-solution.sh` runs it
non-interactively (see [Fleet Deploy via Landscape](landscape-fleet-deploy.md)). Inline:

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
export PATH="$HOME/.local/bin:$PATH"

# Onboard the runtime (accepts defaults for the base install)
nemoclaw onboard

# Wire inference to Plane 1 on this host
openshell provider create \
  --name vllm-local \
  --type openai \
  --credential OPENAI_API_KEY=local \
  --config base_url=http://host.docker.internal:8000/v1

openshell inference set --provider vllm-local --model nvidia/nemotron-3.5-lightning
openshell status              # Connected
```

## 3. Policy tiers

Every sandbox runs under a policy that governs filesystem, network, and
subprocess boundaries. Tier semantics follow NemoClaw's own tiers; use the policies NVIDIA's installer provides and review what "standard" allows before approving it:

| Tier | Filesystem | Network | Subprocess | When to use |
|------|------------|---------|------------|-------------|
| `strict` | Read-only allowlist | Egress denied except whitelist | Denied | First evaluation of an untrusted agent |
| `standard` | Landlock + workspace write | Egress allowed to same host + configured MCP servers | Common CLIs allowed | Enterprise default |
| `permissive` | Broad workspace access | Broad egress | Broad subprocess | Never in production; internal experimentation only |

Apply at sandbox create time. **Filesystem landlock cannot be retrofitted** on
a running sandbox — network policy can be applied live.

## 4. Validation checklist

Before handing a host to a developer or agent, confirm:

| Check | Command | Expected |
|-------|---------|----------|
| Plane 1 model loaded | `curl -s :8000/v1/models` | Lists `nemotron-lightning` |
| Plane 1 health | `curl -sf :8000/health` | HTTP 200 |
| OpenShell connected | `openshell status` | `Connected` |
| Sandbox creates | `openshell sandbox create test --policy solutions/openclaw-on-nemoclaw/policy/standard.sample.yaml` | `Ready` |
| Sandbox reaches LLM | Chat completion from inside sandbox | Non-error response |

## 5. Monitoring

- **vLLM** exposes `/metrics` — the tokenomics Grafana started by each recipe
  (URL printed by the recipe) covers tokens, cost vs cloud, utilisation, TTFT / ITL, KV-cache, queue. Sustained KV-cache > 80 % → shorten context length
  or reduce concurrency.
- **NemoClaw** emits agent telemetry (task success rate, agent turns,
  tool-call counts).
- **GPU** telemetry via NVIDIA DCGM exporter (recommended add-on).

## 6. Lifecycle

| Operation | How |
|-----------|-----|
| **Update the LLM** | Change the recipe's model tag, re-run the recipe. |
| **Update the agent runtime** | Re-run the NemoClaw installer. |
| **Rotate `HF_TOKEN`** | Update in the secret store; restart vLLM. |
| **Add a new agent** | Create a new sandbox with the appropriate policy tier. |
| **Uninstall** | `docker rm -f` the vLLM container + Plane 2 uninstall per NVIDIA installer. |

Never commit HF tokens or credentials to the repository; use environment
variables or a secrets manager. The vLLM endpoint takes no API key by default
— front it with the org gateway/proxy for AD/LDAP-backed auth on multi-user
tiers.

## 7. Scale (dev → prod)

| From | To | Trigger (measured) | How |
|------|----|--------------------|-----|
| Single user (**S**, GB10 / T2) | Small team (**M**, T4) | > 4 concurrent interactive agents, or agent-turn p50 degrading past your SLA | TP=2 or 2× instances on T4 |
| Team (**M**) | App host (**L**, GB300 / T6) | > 4 concurrent agents sustained, or longer contexts needed | Multi-instance on T6 (1 vLLM per GPU + proxy) or single instance on GB300 |

Measured per-tier agent envelopes (wall p50, Hermes-shaped harness):
[Solution overview](README.md#benchmarks-performance-validation).

## 8. Common issues

| Symptom | Fix |
|---------|-----|
| vLLM never becomes healthy | Weights download on first boot (~20 GB). Watch `docker logs` for `Application startup complete.` |
| Sandbox network policy blocks Plane 1 | Add `host.docker.internal:8000` to the sandbox network policy. |
| `openshell policy set` doesn't take effect on filesystem | Filesystem landlock is set at sandbox create time only. Recreate the sandbox with the desired policy. |
| Rootless Docker + `--ulimit memlock=-1` fails | Set `NEMOTRON_LIGHTNING_ROOTLESS=1` before running the recipe. |
| Agent tool calls return as plain text | Model served without the matching `--tool-call-parser` — use the recipe for that model. |

## Related

- [Solution overview](README.md) — sizing, benchmarks.
- [Developer Deploy Guide](deploy-guide-dev.md) — developer quick-start.
- [`docs/recipes/`](../../docs/recipes/) — serving recipe catalog ·
  [S/M/L Sizing](../../docs/sizing.md) — tier framework.
- [Hermes on NemoClaw](../hermes-on-nemoclaw/) — shipping Hermes agent
  on top of this runtime.
- [Agentic Coding](../agentic-coding/) — coding assistant sharing the
  same serving layer.
