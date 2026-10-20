# Agentic Coding — IDE & CLI Agent Integration

How AI engineers and developers connect coding tools to the locally-served model.
The endpoint is **OpenAI-compatible**, so any tool that accepts a custom base URL
works. This guide covers four validated tools — [OpenCode](https://opencode.ai/), [Claude Code](https://claude.com/claude-code),
[Continue.dev](https://continue.dev/), and [Codex](https://github.com/openai/codex) — plus [GitHub Copilot](https://github.com/features/copilot) CLI (BYOK, configured per
upstream docs) and generic OpenAI-compatible clients.

## Connection details

| Setting | Value |
|---------|-------|
| **Base URL** | `http://<deskside-host>:8000/v1` |
| **Model name** | `nvidia/nemotron-3.5-lightning` (served name; see the recipe) |
| **API key** | Any non-empty string for direct local use; a real key when fronted by the gateway |
| **Streaming** | Supported (recommended for interactive coding) |

Replace `<deskside-host>` with `localhost` for local use, or the host IP/hostname
for remote access.

## Context & output limits — align every client to the recipe you run

Agent CLIs send tens of thousands of tokens of system prompt + tool schemas and
often ask for 16–32K output tokens. A client that does not know the server window
gets opaque HTTP 400 "maximum context length" errors or compaction loops
The window is a **recipe setting**, not a model constant:

| Recipe | Served name(s) | `--max-model-len` (window) | Recommended client `max_output` / prompt budget* |
|--------|----------------|---------------------------:|-------------------------------------------------:|
| `gb10` Lightning | `nvidia/nemotron-3.5-lightning` (aliases `nemotron-lightning`, `lightning`) | 200000 | 16384 / 182592 |
| `precision` Lightning (T2/T4/T6) | same | 200000 | 16384 / 182592 |
| `gb300` Lightning | same | 200000 | 16384 / 182592 |
| `gb10` [Qwen3.8-27B](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4) | `qwen3.8-27b` | 262144 | 16384 / 244736 |
| `precision` Flash-Next | `qwen3.8-flash-next` | 262144 | 16384 / 244736 |
| `gb300` [GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) | `glm-5.3-flash` | 262144 | 16384 / 244736 |
| `precision` [Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4) | `nvidia/nemotron-3.5-super-vl` (alias `nemotron-3.5-super-vl`) | 200000 | 16384 / 182592 |
| `gb300` Nemotron 3.5 Super VL (L default) | same | 262144 | 16384 / 244736 |

\*Rule (`recipes/lib/common.sh: ds_client_limits`): `max_output = min(16384, window/8)`
rounded to 512 (never below 512 — reasoning models need room to answer);
`prompt budget = window − max_output − 1024` safety margin. If you override
`--max-model-len`, the numbers change — do not copy them from this table.

**Do not hand-copy.** Every recipe prints these limits in its `READY {...}` line
(`max_model_len`, `client_max_output_tokens`, `client_prompt_budget_tokens`), and this
generates paste-ready configs for OpenCode, Codex, Continue, Claude Code and Copilot CLI
from the *running* endpoint:

```bash
recipes/lib/client-config.sh --port 8000 --served nvidia/nemotron-3.5-lightning --host <deskside-host>
# or one tool:  --tool opencode|codex|continue|claude|copilot
```

The generated key names (`limit.context/output`, `model_context_window`,
`defaultCompletionOptions`, `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, `COPILOT_PROVIDER_MAX_*`)
come from each client's documentation and are **not validated against client binaries
here** — confirm against your installed version. Every agentic-coding recipe now
serves a 200K window (Copilot's recommended ≥128K is covered); raise
`--max-model-len` further (costs KV cache, i.e. concurrency) when a task needs it.

Protocol support observed on the live GLM-5.3-Flash image
(`vllm/vllm-openai:glm53-flash-arm64-cu130`, 2026-10-19): `/v1/chat/completions`,
`/v1/responses` (Codex) and `/v1/messages` (Claude Code) all returned HTTP 200. The
Lightning and Super VL recipes were not re-probed — check
`curl -s localhost:8000/v1/messages ...` on your pinned image before relying on Claude Code.

---

## OpenCode (CLI coding agent)

Reference: [CLI Coding Agent (DGX Spark)](https://build.nvidia.com/spark/cli-coding-agent).

### Install

```bash
# npm (globally)
npm install -g opencode-ai

# or run directly
npx opencode-ai
```

### Configure

Create `~/.config/opencode/config.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "dell-deskside-agentic": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Dell Deskside Agentic AI Solutions (local vLLM)",
      "options": {
        "baseURL": "http://localhost:8000/v1",
        "apiKey": "local"
      },
      "models": {
        "nvidia/nemotron-3.5-lightning": {
          "name": "Nemotron 3.5 Lightning - local"
        }
      }
    }
  },
  "model": "dell-deskside-agentic/nvidia/nemotron-3.5-lightning"
}
```

### Verify

```bash
opencode
# In the OpenCode CLI, type: "Write a Python function to reverse a string."
# Expected: model generates code using the local vLLM endpoint
```

---

## Claude Code (Anthropic CLI)

### Install

```bash
npm install -g @anthropic-ai/claude-code
```

### Configure

Create `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8000",
    "ANTHROPIC_AUTH_TOKEN": "local",
    "ANTHROPIC_MODEL": "nvidia/nemotron-3.5-lightning",
    "ANTHROPIC_SMALL_FAST_MODEL": "nvidia/nemotron-3.5-lightning"
  }
}
```

Or set environment variables:

```bash
export ANTHROPIC_BASE_URL="http://localhost:8000"
export ANTHROPIC_AUTH_TOKEN="local"
export ANTHROPIC_MODEL="nvidia/nemotron-3.5-lightning"
export ANTHROPIC_SMALL_FAST_MODEL="nvidia/nemotron-3.5-lightning"
claude
```

### Verify

```bash
claude "What is 2 + 2?"
# Expected: response from the local Nemotron model
```

---

## Continue.dev (VS Code / JetBrains)

Reference: [Vibe Coding in VS Code (DGX Spark)](https://build.nvidia.com/spark/vibe-coding).

### Install

Install the [Continue extension](https://continue.dev/) from the VS Code or
JetBrains marketplace.

### Configure

Create `~/.continue/config.yaml`:

```yaml
name: Dell Deskside Agentic AI Solutions
version: 0.0.1
schema: v1
models:
  - name: Nemotron 3.5 Lightning (local vLLM)
    provider: openai
    model: nvidia/nemotron-3.5-lightning
    apiBase: http://localhost:8000/v1
    apiKey: local
    roles:
      - chat
      - edit
      - apply
  - name: Nemotron 3.5 Lightning (autocomplete)
    provider: openai
    model: nvidia/nemotron-3.5-lightning
    apiBase: http://localhost:8000/v1
    apiKey: local
    roles:
      - autocomplete
```

Or use the JSON format (`~/.continue/config.json`):

```json
{
  "models": [
    {
      "title": "Dell Deskside Agentic Coding",
      "provider": "openai",
      "model": "nvidia/nemotron-3.5-lightning",
      "apiBase": "http://localhost:8000/v1",
      "apiKey": "local"
    }
  ]
}
```

### Verify

Open VS Code, open the Continue sidebar (Ctrl+L), and ask:
"Write a unit test for the function under the cursor." A response confirms the
model, base URL, and streaming are wired correctly.

---


## Codex (OpenAI CLI)

Codex — OpenAI's terminal coding agent — speaks the OpenAI **Responses API**.
The `vllm/vllm-openai` images serve `/v1/responses`, so Codex needs only a
custom provider entry, no proxy.

### Configure

```toml
# ~/.codex/config.toml
model_provider = "deskside"
model = "nvidia/nemotron-3.5-lightning"

[model_providers.deskside]
name = "Dell Deskside vLLM"
base_url = "http://localhost:8000/v1"
env_key = "DESKSIDE_API_KEY"
wire_api = "responses"
```

### Run

```bash
export DESKSIDE_API_KEY=local
codex exec --skip-git-repo-check "Summarize this repository in 3 bullets"
```

### Verify

```bash
# One-shot round trip — tool calling is exercised automatically
# (Codex always ships its shell tool in the request).
DESKSIDE_API_KEY=local codex exec --skip-git-repo-check --sandbox read-only \
  "Run echo CODEX_OK and report exactly what it printed"
```

Notes: a `Model metadata for ... not found` warning is expected for local
served names and is harmless. The Codex sandbox uses bubblewrap, which needs
unprivileged user namespaces (enabled by default on Ubuntu 24.04). Recent
Codex releases require `wire_api = "responses"`; there is no `chat` fallback.

---

## GitHub Copilot CLI (BYOK)

Reference: [Adding LLM models to GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models).

Copilot CLI supports bring-your-own-key providers; the default `openai`
provider type covers *any* OpenAI Chat Completions-compatible endpoint — [vLLM](https://github.com/vllm-project/vllm)
is explicitly supported. The model must support **tool calling** and
**streaming** (Lightning does both). GitHub recommends ≥128K context for best
results; the recipe serves 200K by default — raise `--max-model-len` further if
AI memory allows.

### Configure

Set provider environment variables before starting the CLI. No API key is
required for an unauthenticated local endpoint; use a real key when fronted
by the gateway:

```bash
export COPILOT_PROVIDER_BASE_URL="http://localhost:8000/v1"
export COPILOT_PROVIDER_API_KEY="local"   # any non-empty string; omit if truly unauthenticated
export COPILOT_MODEL="nvidia/nemotron-3.5-lightning"
copilot
```

### Offline mode (air-gapped desks)

```bash
export COPILOT_OFFLINE=true
```

This keeps the CLI from contacting GitHub's servers. Full network isolation
holds only when `COPILOT_PROVIDER_BASE_URL` also points at a local endpoint
(upstream caveat — a remote base URL still ships prompts off-box).

### Verify

In the Copilot CLI, ask: "List the files under `src/` and summarize the entry
point." A streamed reply that used file tools confirms model, tools, and the
local endpoint are wired.

> **IDE extension:** this BYOK path is for the **Copilot CLI**. Copilot inside
> VS Code / JetBrains uses GitHub-hosted models unless your org enables custom
> models there — on locked-down desks use the CLI, or one of the tools above.

---

## Generic CLI agents (OpenAI-compatible)

Most CLI agents (Aider, Cline, etc.) read standard OpenAI env vars:

```bash
export OPENAI_BASE_URL="http://localhost:8000/v1"
export OPENAI_API_KEY="local"
export OPENAI_MODEL="nvidia/nemotron-3.5-lightning"
```

### JetBrains AI Assistant

Use an OpenAI-compatible AI assistant plugin; set the base URL to
`http://<host>:8000/v1` and the model to `nvidia/nemotron-3.5-lightning`.

---

## AGENTS.md skills

`AGENTS.md` is a widely used convention across coding agents. Point coding agents at the
project's `AGENTS.md` so they inherit repo conventions and skills.

---

## Application compatibility matrix

| Tool | Connection method | Chat | Autocomplete | Tool calling | Validated |
|------|------------------|------|-------------|-------------|-----------|
| **OpenCode** | OpenAI-compatible provider | Yes | N/A (CLI) | Yes | GB10 |
| **Claude Code** | Anthropic base URL override | Yes | N/A (CLI) | Yes | GB10 |
| **Continue.dev** | OpenAI provider config | Yes | Yes | No | GB10 |
| **Codex** | config.toml provider (Responses API) | Yes | N/A (CLI) | Yes | GB300 |
| **GitHub Copilot CLI** | BYOK env vars (OpenAI-compatible) | Yes | N/A (CLI) | Required | Upstream docs |

---


## Running coding agents safely (read before pointing an agent at a shared box)

Coding agents run shell commands with **your user's privileges** and read repository content that may carry prompt
injection. This repo does not (yet) sandbox them for the Agentic Coding solution (the NemoClaw solutions
use OpenShell policy tiers for this purpose). Until then:
* keep the client in its **read-only / ask-before-run** permission mode (e.g. Codex `--sandbox read-only`); do not use
  "skip permissions" switches on a machine that holds credentials;
* give each agent/user its **own API key** once you front the endpoint (`DESKSIDE_API_KEY`, or the LiteLLM front door's keys)
  so one runaway agent can be identified and revoked — per-key rate limits need a gateway;
* do not expose the endpoint beyond the LAN segment it is needed on (`--bind`); it is unauthenticated by default.

## Multi-user note

For shared/team use, point IDEs at the **gateway URL** (not the raw `:8000`) so
auth and rate limiting apply. See [IT-Admin Guide](it-admin-guide.md).
