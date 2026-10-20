# OpenClaw on NemoClaw — Developer Quick-Start

> **Who this is for:** developers standing up the [NemoClaw](https://github.com/NVIDIA/NemoClaw) runtime on a Dell
> workstation to build a custom tool-using agent.
>
> **IT fleet path:** [IT-Admin Guide](it-admin-guide.md).
>
> **Shipping agent:** if you want the ready-to-use tool-using agent, see
> [Hermes on NemoClaw](../hermes-on-nemoclaw/) instead.

## Prerequisites

- Ubuntu 24.04 LTS or newer on Dell Pro Precision 9 towers and Dell Pro Precision with GB300; GB10 systems ship with DGX OS.
- [Docker](https://www.docker.com/) CE + NVIDIA Container Toolkit — `docker run --rm --gpus all
  nvidia/cuda:12.4.0-base-ubuntu24.04 nvidia-smi` should succeed.
- Node.js ≥ 20 (installed via `nvm` by the NemoClaw installer if missing).
- [Hugging Face](https://huggingface.co/) token (`HF_TOKEN`) with access to the [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4)
  NVFP4 model, **or** weights pre-cached in `~/.cache/huggingface`.
- Outbound network to `nvidia.com`, `github.com`, `huggingface.co` for the
  initial install.

## 1) Plane 1 — local LLM

Pick the recipe matching your hardware and serve on port 8000:

| Dell system | Recipe |
|-------------|--------|
| Dell Pro Precision with GB10 | `recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` |
| Precision T2 / T4 / T6 (Blackwell) | `recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` |
| Dell Pro Precision with GB300 | `recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` |

_Commands in this guide run from the repository root (`git clone` this repo and `cd` into it)._

```bash
recipes/<platform>/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
curl -s http://localhost:8000/v1/models
```

Prefer `--gpu-memory-utilization 0.70` to leave headroom for the agent
workload (the recipes default to this for GB10; adjust to 0.85–0.90 on M / L
when you know your agents are LLM-heavy).

**Model alternatives (same OpenAI-compatible API, tool-calling verified).**
The serving recipes bake the tool/reasoning parsers each model needs — do not
swap the model without matching parsers, or agent tool-calling fails silently:

| Tier | Alternative model | Recipe | Tool parser |
|------|-------------------|--------|-------------|
| S | [Qwen3.8 27B NVFP4](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4) (+ MTP) | `recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh` | `qwen3_coder` |
| M | [Qwen3.8-Flash-Next NVFP4](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4) (MTP ×3, engram CPU offload) | `recipes/precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh` | `qwen3_xml` |
| L | [GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) NVFP4 (320B/18B-active MoE, 262K ctx) | `recipes/gb300/vllm/docker-glm-5.3-flash-nvfp4.sh` | `glm47` |

## 2) Plane 2 — NemoClaw + OpenShell

Plane 2 uses NVIDIA's shipping installer, which keeps you on NVIDIA's release cadence
(for a fleet, `scripts/landscape/deploy-solution.sh` runs it non-interactively across a fleet):

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
export PATH="$HOME/.local/bin:$PATH"
source "$HOME/.nvm/nvm.sh" && nvm use --lts

# Onboard the runtime (interactive; accept defaults for the base install)
nemoclaw onboard
```

## 3) Wire inference to Plane 1

```bash
openshell provider create \
  --name vllm-local \
  --type openai \
  --credential OPENAI_API_KEY=local \
  --config base_url=http://host.docker.internal:8000/v1

openshell inference set --provider vllm-local --model nvidia/nemotron-3.5-lightning
openshell status              # Connected
```

## 4) Create a sandbox

Every sandbox runs under a policy tier (`strict` / `standard` /
`permissive` — see [Solution overview](README.md#architecture)). Start custom agents
on `standard`; evaluate untrusted code on `strict`.

```bash
# Create a sandbox from the quick-start sample policy (review it, then adopt or edit it)
openshell sandbox create my-agent --policy solutions/openclaw-on-nemoclaw/policy/standard.sample.yaml

# List sandboxes
openshell sandbox list        # my-agent | Ready

# Enter the sandbox with a shell (for exploration)
openshell sandbox shell my-agent
```

Note: filesystem landlock is fixed at sandbox create time — pick the tier
before you create. Network policy can be adjusted live.

## 5) Verify LLM access from inside the sandbox

```bash
# Inside the sandbox
curl -s http://host.docker.internal:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "nvidia/nemotron-3.5-lightning",
    "messages": [{"role":"user","content":"Reply with exactly: PLANE_1_OK"}],
    "max_tokens": 32
  }' | jq -r '.choices[0].message.content'
```

Expected: `PLANE_1_OK`. Nemotron 3.5 Lightning is a reasoning model — for real
turns give clients `max_tokens >= 512` (smaller budgets are consumed by the
thinking trace).

## Where to go next

- **Build your custom agent.** NemoClaw provides the runtime, sandbox, and
  policy — your agent code lives inside the sandbox and calls the local LLM
  through the wired provider.
- **Wire MCP tools.** Add your MCP servers and register them
  with the sandbox. Credentials stay outside the sandbox.
- **Budget tool-execution cost.** If one agent turn triggers multiple
  sequential MCP calls, tool cost often dominates LLM cost — measure it early.
- **Use the shipping [Hermes](https://hermes-agent.nousresearch.com/) agent.** If you don't want to write a custom
  agent, see [Hermes on NemoClaw](../hermes-on-nemoclaw/) — same
  runtime, ready-made agent.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| [vLLM](https://github.com/vllm-project/vllm) `/v1/models` returns 404 | Server still loading weights. Watch `docker logs` for `Application startup complete.` |
| NemoClaw installer fails on Node.js version | Ensure `nvm` is loaded (`source "$HOME/.nvm/nvm.sh"`) and Node.js LTS is active. |
| Sandbox cannot reach Plane 1 endpoint | Use `host.docker.internal:8000` rather than `127.0.0.1:8000` from inside the [OpenShell](https://github.com/NVIDIA/OpenShell) sandbox. |
| `openshell status` never reaches Connected | Confirm the provider config used a reachable base URL and a model name that matches one of the `--served-model-name` aliases. |
| Model replies are empty with `finish_reason=length` | Reasoning trace ate the token budget — raise `max_tokens` to ≥ 512. |

## Related

- [Solution overview](README.md) — use cases, sizing, and
  measured per-tier concurrency (Benchmarks & performance).
- [IT-Admin Guide](it-admin-guide.md) — IT-admin fleet path.
- [Inference Stack & Models](../../docs/stack.md) — inference-stack options.
- [Hermes on NemoClaw](../hermes-on-nemoclaw/) — shipping agent on top
  of this runtime.
- [Agentic Coding](../agentic-coding/) — coding assistant sharing the
  same serving layer.
