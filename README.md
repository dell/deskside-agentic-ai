# [Dell Deskside Agentic AI](https://www.dell.com/en-us/shop/ai/lp/deskside-agentic-ai) Solutions for NVIDIA

[![docs: GitHub Pages](assets/badges/docs.svg)](https://dell.github.io/deskside-agentic-ai/)

Open-source reference architectures for enterprise agentic AI on Dell deskside
systems powered by NVIDIA. Each solution pairs NVIDIA reference material with S/M/L
sizing, a runnable deployment recipe, measured performance and an IT-Admin guide,
so IT teams know what to deploy and what to expect.

## Solutions

| Solution | What it delivers |
|----------|------------------|
| **[Agentic Coding](solutions/agentic-coding/)** | A private, on-deskside AI coding assistant — code generation, explanation, refactoring, and agentic CLI/IDE workflows served locally behind an OpenAI-compatible API. |
| **[Agentic Video Search & Summarization](solutions/agentic-vss/)** | Natural-language search, Q&A, and summarization over local video libraries — vision-language plus LLM serving on the same deskside tiers. |
| **[OpenClaw on NemoClaw](solutions/openclaw-on-nemoclaw/)** | The [OpenClaw](https://openclaw.ai/) assistant on NVIDIA's NemoClaw runtime — policy engine, [OpenShell](https://github.com/NVIDIA/OpenShell) sandbox, and tool-using agents on a locally served LLM. |
| **[Hermes on NemoClaw](solutions/hermes-on-nemoclaw/)** | [Nous Research](https://nousresearch.com/)' [Hermes Agent](https://hermes-agent.nousresearch.com/) harness on the [NemoClaw](https://github.com/NVIDIA/NemoClaw) runtime — served and sandboxed fully on Dell deskside hardware. |
| **[Higher Education AI Lab](solutions/higher-ed-ai-lab/)** | Repeatable design for university AI teaching labs — shared serving tiers, per-course provisioning, and a curriculum built on the other solutions. |

## Where to look

- **Docs site (GitHub Pages):** the [`docs/`](docs/) folder is the site source,
  served directly from `/docs`: solution pages, sizing, inference stack, recipes
  and reference material.
- **Solutions:** [`solutions/`](solutions/) — every solution template
  (README + IT-Admin guide + developer guide).
- **Scope:** [`docs/scope.md`](docs/scope.md)
- **Operations:** [`docs/operations.md`](docs/operations.md) (ports, co-tenancy, resources, prerequisites, air-gap) · [`docs/topology.md`](docs/topology.md) (TP vs DP per workload) · [`monitoring/`](monitoring/README.md) (tokenomics dashboard).
- **Deployment recipes:** [`recipes/`](recipes/) — self-contained `docker` serve
  scripts per platform/tier.

## Getting started (Agentic Coding)

Serve the default coding model on a Dell deskside system powered by NVIDIA GB10:

```bash
recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
# blocks until the endpoint is truly ready (first run downloads ~21 GB of weights), starts the
# tokenomics dashboard, then prints:  READY {"base_url":"http://localhost:8000/v1", ...}
curl -s http://localhost:8000/v1/models
recipes/gb10/vllm/health-nemotron-3.5-lightning-nvfp4.sh   # field-debug health report any time
```

Prerequisites: Docker + NVIDIA Container Toolkit, ~25 GB free disk, outbound HTTPS to Hugging Face
(or a pre-seeded cache). Add `--dry-run` to preview without changing anything. Other platforms: see the
[recipe catalog](recipes/README.md).

Then point a CLI/IDE agent at `http://<host>:8000/v1` with model
`nvidia/nemotron-3.5-lightning` (reasoning model — use `max_tokens >= 512`; generate window-aligned client
configs with `recipes/lib/client-config.sh`). See the
[IT-Admin guide](solutions/agentic-coding/it-admin-guide.md) and
[IDE integration](solutions/agentic-coding/ide-integration.md) for the full setup.

## License

Released under the Apache License 2.0 — see [LICENSE](LICENSE).
