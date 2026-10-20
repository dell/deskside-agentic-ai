# Changelog

Release notes for Dell Deskside Agentic AI Solutions for NVIDIA. Every
performance figure in a release carries provenance through the machine-readable
record in `tests/data/latest/sizing.yaml` and the raw ladder data under
`tests/data/`.

## 1.0.0 — October 20, 2026

First public release: **five Solution Templates** on **five supported Dell
deskside platforms powered by NVIDIA**, with measured capacity envelopes,
executable serving recipes, and operator guides.

### Solution Templates

| Template | Category | What it delivers |
|----------|----------|------------------|
| [Agentic Coding](../solutions/agentic-coding/README.md) | Horizontal | Private coding assistant — CLI/IDE agents behind an OpenAI-compatible API, with measured per-platform concurrency envelopes |
| [Agentic Video Search & Summarization](../solutions/agentic-vss/README.md) | Vertical | Natural-language search, Q&A, and summarization over local video — LLM + vision-language serving co-located on one system |
| [OpenClaw on NemoClaw](../solutions/openclaw-on-nemoclaw/README.md) | Horizontal | The OpenClaw assistant on NVIDIA's NemoClaw runtime — policy engine, OpenShell sandbox, tool-using agents on a locally served LLM |
| [Hermes on NemoClaw](../solutions/hermes-on-nemoclaw/README.md) | Horizontal | Nous Research' Hermes Agent harness on the NemoClaw runtime — served and sandboxed fully on Dell deskside hardware |
| [Higher Education AI Lab](../solutions/higher-ed-ai-lab/README.md) | Vertical | University AI teaching labs — shared serving tiers, per-course provisioning, seat resets, and a curriculum built on the other templates |

### Supported platforms

| Platform | Memory | Tier |
|----------|--------|------|
| Dell Pro Precision with GB10 (DGX Spark class, aarch64) | 128 GB unified | S · M (1:1 seats) |
| Dell Pro Precision 9 T2 (1× RTX PRO 6000 Blackwell) | 96 GB | S |
| Dell Pro Precision 9 T4 (2× RTX PRO 6000 Blackwell) | 192 GB | M |
| Dell Pro Precision 9 T6 (5× RTX PRO 6000 Blackwell) | 480 GB | L |
| Dell Pro Precision with GB300 (DGX Station class, aarch64) | 252 GB HBM3e | L |

### In this release

- **Serving recipes** (`recipes/`): eight pinned, GPU-tuned vLLM recipes across
  GB10 / Precision / GB300, all sharing one readiness contract — block until
  healthy, emit a machine-readable `READY` line, meaningful exit codes — plus
  paired health wrappers, a replica launcher, and a LiteLLM router for
  multi-instance serving.
- **Measured envelopes**: agent- and chat-shape throughput ladders
  ([AIPerf](https://github.com/ai-dynamo/aiperf)) per platform, per-session
  concurrency envelopes at explicit floors, and per-workload TP-vs-DP
  topology data.
- **Fleet and offline tooling**: Canonical Landscape deployment payloads,
  air-gap image packaging, LAN multicast distribution for large lab assets, and
  scripted NemoClaw installation.
- **Tokenomics monitoring**: Prometheus + Grafana started with every recipe,
  alert rules, per-session throughput views.
- **Architecture views**: every Solution Template's guide opens with an SVG
  architecture diagram (the Higher Education template adds a campus usage and
  connectivity view), and the interactive Architecture Builder exports any of
  them as SVG, PNG, or HTML.
- **This docs site**, generated from the Markdown sources in the repo, with the
  same navigation on every page and a link to the source repository in the
  header.

Tagged release: [`v1.0.0`](https://github.com/dell/deskside-agentic-ai/releases/tag/v1.0.0).

## Release policy

Version bumps here track the Solution Templates and their measured data:
major = breaking changes to the recipe contract or template structure; minor =
new templates, platforms, or measured tiers; patch = recipe fixes and
corrections. Each entry names what was measured and where the raw data lives.
