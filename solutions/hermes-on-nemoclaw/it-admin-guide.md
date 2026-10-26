# Hermes on NemoClaw — IT-Admin Deployment Guide

> **Who this is for:** enterprise IT admins rolling out the deskside [Hermes](https://hermes-agent.nousresearch.com/)
> agent stack ([NemoClaw](https://github.com/NVIDIA/NemoClaw) + Hermes + local [vLLM](https://github.com/vllm-project/vllm)) on Dell fleets.
>
> **Developer quick-start:** [Developer Deploy Guide](deploy-guide-dev.md).

This guide covers a **fleet install** of the Hermes on NemoClaw solution on
Dell workstations. It assumes:

- Dell Pro Precision with GB10/GB300 or Dell Pro Precision 9 tower (T2/T4/T6) hardware with NVIDIA GPUs (S / M / L tiers).
- Ubuntu 24.04 LTS or newer on Dell Pro Precision 9 towers and Dell Pro Precision with GB300; GB10 systems ship with DGX OS.
- A control node with administrative access to every target host.
- One IdP-integrated account per developer / operator using the agent.

## Overview

The solution deploys in planes that can be installed and upgraded
independently:

| Plane | Contents | Install path |
|-------|----------|--------------|
| **Plane 0 — Prerequisites** | [Docker](https://www.docker.com/) CE + NVIDIA Container Toolkit + secrets + disk for weights | Ubuntu package install |
| **Plane 1 — Serving** | vLLM + Nemotron + [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) | Per-platform recipe from [`recipes/`](../../recipes/) (Docker Compose) |
| **Plane 2 — Agent** | NemoClaw → [OpenShell](https://github.com/NVIDIA/OpenShell) → Hermes sandbox + policy | NVIDIA installer + `nemohermes` onboard |

The **same Plane 1 endpoint** is reusable across other solutions in this
repository ([Agentic Coding](../agentic-coding/), video search, etc.) — you do
not need one vLLM instance per solution on the same workstation.

## Plane 0 — Prerequisites

Every target host must have:

- **Docker CE ≥ 24** and **NVIDIA Container Toolkit** — verify with:
  ```bash
  docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu24.04 nvidia-smi
  ```
- **[Hugging Face](https://huggingface.co/) token** (`HF_TOKEN`) with access to the [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4)
  NVFP4 model, **or** the weights already staged in `~/.cache/huggingface`.
- **~30 GB free** in the Hugging Face cache path.
- **Outbound network** access to `huggingface.co`, `nvidia.com`, `github.com`
  from Plane 2 hosts for the initial NemoClaw installer run.

Optional but recommended:

- Prometheus + Grafana already stood up on the box (Plane 1 recipes bring
  their own — you can either reuse or run co-tenant).
- A reverse proxy (nginx / Caddy / Traefik) in front of vLLM if agents will
  be reached from anywhere other than `localhost`.

## Plane 1 — Serving

### Single host — run the recipe

Pick the recipe matching the host's platform and run it directly:

_Commands in this guide run from the repository root (`git clone` this repo and `cd` into it)._

```bash
recipes/<platform>/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
curl -sf http://localhost:8000/health && echo VLLM_OK
```

Recipes automatically apply the validated flag set (MoE backend, KV-cache
dtype, tool-call parser) — see
[Deployment Recipes](../../recipes/README.md).

| Platform | Recipe directory |
|----------|------------------|
| Dell Pro Precision with GB10 | [`recipes/gb10/vllm/`](https://github.com/dell/deskside-agentic-ai/tree/main/recipes/gb10/vllm) |
| Dell Pro Precision 9 T2 / T4 / T6 (1× / 2× / 5× RTX PRO 6000) | [`recipes/precision/vllm/`](https://github.com/dell/deskside-agentic-ai/tree/main/recipes/precision/vllm) |
| Dell Pro Precision with GB300 | [`recipes/gb300/vllm/`](https://github.com/dell/deskside-agentic-ai/tree/main/recipes/gb300/vllm) |

### Multi-host fleet

Use Canonical Landscape script execution
([Fleet Deploy via Landscape](../agentic-coding/landscape-fleet-deploy.md)) or your own
automation; every recipe blocks until ready and exits non-zero on failure. Map hosts to
per-tier recipes ([recipe catalog](../../recipes/README.md)); `HF_TOKEN` is needed unless
weights are pre-cached.

### Verify Plane 1

Once vLLM is up, the following should all succeed:

```bash
curl -sf http://localhost:8000/health           # 200 OK
curl -s  http://localhost:8000/v1/models        # lists nemotron-lightning
curl -sfI http://localhost:3000/login | head -1 # Grafana 200
curl -sf  http://localhost:9090/-/healthy       # Prometheus OK
```

## Plane 2 — Agent

NemoClaw and Hermes are installed via NVIDIA's official installer — this guide
only covers the wire-up to Plane 1 and the operator-tier settings. (For a fleet,
`scripts/landscape/deploy-solution.sh` runs the install non-interactively; inline path below.)

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash

# Onboard the runtime. Choose Hermes / nemohermes when the wizard prompts.
nemoclaw onboard

# Wire agent inference to the Plane 1 endpoint on this host:
openshell provider create \
  --name vllm-local \
  --type openai \
  --credential OPENAI_API_KEY=local \
  --config base_url=http://host.docker.internal:8000/v1

openshell inference set --provider vllm-local --model nvidia/nemotron-3.5-lightning
openshell status
```

### Agent policy

Every Hermes sandbox runs under a NemoClaw policy that governs filesystem
access, network egress, and subprocess boundaries. Ship the **standard** tier
policy for enterprise deployments — never leave `permissive` in production.

Three policy tiers ship with NemoClaw (standard, strict, permissive). Save
your tier as a policy file and apply it at sandbox creation:

```bash
nemohermes create <sandbox-name> --policy solutions/hermes-on-nemoclaw/policy/standard.sample.yaml
```

Filesystem landlock and network policy behave differently:

- **Filesystem landlock** must be set at sandbox **create** time. `openshell
  policy set` cannot retrofit filesystem constraints on a running sandbox.
- **Network policy** can be applied live via `openshell policy set` on a
  running sandbox.

## Validation checklist

Before handing a host to a developer, confirm:

| Check | Command | Expected |
|-------|---------|----------|
| Plane 1 model loaded | `curl -s :8000/v1/models` | Lists `nemotron-lightning` |
| Plane 1 health | `curl -sf :8000/health` | HTTP 200 |
| Grafana reachable | `curl -sfI :3000/login` | HTTP 200 |
| Prometheus healthy | `curl -sf :9090/-/healthy` | HTTP 200 |
| OpenShell connected | `openshell status` | `Connected` |
| Hermes sandbox ready | `nemohermes <sandbox> status` | `Ready` + Hermes version |
| Tool exec works | `nemohermes <sandbox> exec -- uname -s` | Kernel name |
| Agent oneshot works | `hermes -z 'Reply with exactly: HERMES_Z_OK'` | `HERMES_Z_OK` |

## Monitoring

- **vLLM** exposes `/metrics` (Prometheus format). Each recipe starts the shared tokenomics
  Prometheus + Grafana (`monitoring/README.md`) covering tokens, cost vs cloud, utilisation, TTFT / ITL,
  KV-cache and queue depth.
- **NemoClaw** emits agent-level telemetry (task success rate, agent turns,
  tool-call counts). See NVIDIA NemoClaw documentation for the metric names.
- **GPU** telemetry via NVIDIA DCGM exporter (recommended add-on).

## Lifecycle

| Operation | How |
|-----------|-----|
| **Update the LLM** | Change the recipe's model tag, re-run the recipe. |
| **Update the agent** | Re-run the NemoClaw installer. |
| **Rotate `HF_TOKEN`** | Update the secret in your secret store; restart the vLLM container. |
| **Rollback** | Recipes are idempotent; `docker stop` the current container and re-run with the previous image tag. |
| **Uninstall** | `docker rm -f` the vLLM container + Plane 2 uninstall per NVIDIA installer. |

## Common issues

| Symptom | Fix |
|---------|-----|
| vLLM never becomes healthy | Weights download on first boot (~20 GB). Watch `docker logs <container>` for `Application startup complete.` — usually 1–3 min on cached weights, 10–20 min on cold pull. |
| `nemohermes exec` denied by network policy | Add the local Plane 1 host to the sandbox network policy; prefer `host.docker.internal:8000` over `127.0.0.1:8000`. |
| Rootless Docker + `--ulimit memlock=-1` fails | Set `NEMOTRON_LIGHTNING_ROOTLESS=1` before running the recipe (drops the memlock ulimit). |
| Hermes oneshot exceeds context on first try | Add `model.max_tokens: 4096` to the sandbox Hermes config. |

## Multi-user identity

Hermes inherits the host's identity by default. For multi-user M / L
deployments:

- Front the vLLM endpoint with a reverse proxy that terminates AD / LDAP /
  OIDC and injects the identity into the request.
- Use per-user Hermes sandboxes so tool-execution policies and long-running
  state are scoped per operator.

Identity integration is intentionally out of scope for the base install — the
solution is agent-first; the identity integration is a deployment decision
per site.

## Scale guidance (measured)

| Platform | Concurrent Hermes agents |
|----------|--------------------------|
| Dell Pro Precision with GB10 | 1 – 2 interactive (4 pass) |
| Dell Pro Precision 9 T2 / T4 (1× / 2× RTX PRO 6000) | 1 – 4; on 2-GPU hosts, optionally one vLLM instance per GPU behind a small load balancer |
| Dell Pro Precision 9 T6 · 5× RTX PRO 6000 | 1 – 4 per GPU; one vLLM instance per GPU behind a small router ([LiteLLM](https://www.litellm.ai/) proxy or nginx) |
| Dell Pro Precision with GB300 | 1 – 4+; flat wall-time across the tested range |

Details: [README — Benchmarks & performance](README.md#benchmarks-performance-validation).

## Related

- [README](README.md) — solution overview.
- [Developer Deploy Guide](deploy-guide-dev.md) — single-host developer path.
- [OpenClaw on NemoClaw](../openclaw-on-nemoclaw/) — the same runtime with the default OpenClaw agent, no
  agent.
- [Agentic Coding](../agentic-coding/) — companion solution sharing the
  same Plane 1 serving layer.
- [Deployment Recipes](../../recipes/README.md) — serving recipe catalog.
