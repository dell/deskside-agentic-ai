# Agentic VSS — IT Admin Deployment Guide

> **Who this is for:** enterprise IT admins rolling out the VSS Blueprint
> across a set of Dell deskside systems.
>
> **Developer quick-start:** [Developer Deploy Guide](deploy-guide-dev.md).

## Overview

VSS deploys as a stack of [Docker](https://www.docker.com/) Compose services managed by the upstream
NVIDIA VSS Blueprint. This solution adds Dell-specific sizing, per-platform
model overlays, and a fleet-install path.

| Component | Purpose | Install |
|-----------|---------|---------|
| **VSS Agent + UI** | Interactive UI and API for search / summarization / alerts | Upstream Blueprint (Docker Compose) |
| **VIOS / VST** | Video ingest, embedding, stream understanding | Upstream Blueprint |
| **Vector / graph DB** | Search indexes | Upstream Blueprint |
| **LLM ([vLLM](https://github.com/vllm-project/vllm))** | Summarization, Q&A, alert reasoning | Local vLLM container (per-tier model below) |
| **VLM (vLLM)** | Vision-language reasoning over frames | Local vLLM container ([Nemotron 3 Nano Omni](https://huggingface.co/nvidia/nemotron-3-nano-omni-30b-a3b)) |
| **Phoenix** | Observability | Upstream Blueprint |

## Prerequisites (per host)

- Ubuntu 24.04 LTS or newer on Dell Pro Precision 9 towers and Dell Pro Precision with GB300; GB10 systems ship with DGX OS.
- **Docker CE `28.3.3 ≤ version < 29.5.0`** — upstream VSS is sensitive to
  Docker versions; 29.5.0+ may fail pulling NGC images.
- NVIDIA Container Toolkit.
- Git LFS.
- **NGC API key** (`NGC_CLI_API_KEY`).
- **[Hugging Face](https://huggingface.co/) token** (`HF_TOKEN`) with access to the Nemotron models.
- 50–80 GB free disk for VSS containers + LLM + VLM weights, plus space for
  the video corpus (specific to you).

## Model selection per tier

Use the per-tier LLM default (the VLM is the same across all tiers):

| Dell system | LLM (default · alt) | VLM |
|-------------|----------------------|-----|
| Dell Pro Precision with GB10 (128 GB unified) | `nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4` · alt `nvidia/Qwen3.8-27B-NVFP4` | `nvidia/nemotron-3-nano-omni-30b-a3b` |
| Dell Pro Precision 9 T2 (1× RTX PRO 6000, 96 GB) | `nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4` | `nvidia/nemotron-3-nano-omni-30b-a3b` |
| Dell Pro Precision 9 T4 (2× RTX PRO 6000) | [Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4) · alt `nvidia/Qwen3.8-Flash-Next-NVFP4` | `nvidia/nemotron-3-nano-omni-30b-a3b` |
| Dell Pro Precision with GB300 (252 GB HBM3e, aarch64) | Nemotron 3.5 Super VL · alt `RedHatAI/GLM-5.3-Flash-NVFP4` | `nvidia/nemotron-3-nano-omni-30b-a3b` |

Standalone LLM serving recipes per tier are in the
[recipe catalog](../../recipes/README.md); inside the VSS hybrid stack the
LLM runs co-located with the VLM at reduced memory utilization (see below).
VLM serving command: inline in the
[Developer Deploy Guide](deploy-guide-dev.md).

## Install (per host)

Follow [Developer Deploy Guide](deploy-guide-dev.md) — the developer flow *is*
the fleet flow, run per host. For multi-host rollouts, wrap the steps in
your existing configuration-management tool or Ubuntu
[Landscape](https://ubuntu.com/landscape) script execution
(see [Fleet Deploy via Landscape](../agentic-coding/landscape-fleet-deploy.md) for the
pattern). The upstream VSS Blueprint's Docker Compose is the deployment
unit; your tooling handles inventory, secret distribution, and rollout ordering.

## VLM + LLM co-location on S tier

VSS runs the VLM **and** the LLM on the same GPU in Standard hybrid mode.
This is intentional and validated on the S tier:

- Peak co-located GPU memory: **68.3 GB of 96 GB** (71.4 %), measured on
  Dell Pro Precision 9 T2.
- Both containers use `--gpu-memory-utilization 0.35`.
- **VLM must start before LLM** — vLLM requires the target GPU to have free
  memory at startup.

For M / L tiers with additional GPUs, split VLM and LLM across GPUs and drop
the `0.35` cap.

## Validation checklist

| Check | Command | Expected |
|-------|---------|----------|
| LLM endpoint healthy | `curl -s :30081/v1/models` | Lists LLM model |
| VLM endpoint healthy | `curl -s :30082/v1/models` | Lists VLM model |
| VSS Agent UI reachable | `curl -I :7777` | HTTP 200 |
| VSS health endpoint | `curl -fsS :8000/health` | 200 OK |
| End-to-end smoke test | Ingest → NL query → result | 0 errors |

## Monitoring

- **vLLM** exposes `/metrics` for both LLM and VLM containers — scrape with
  [Prometheus](https://prometheus.io/). Cover request rate, tok/s, TTFT, KV-cache utilization.
- **VSS** exposes ingestion metrics via Phoenix.
- **GPU** telemetry via NVIDIA DCGM exporter.

Extend your [Grafana](https://grafana.com/) dashboards with video-pipeline panels: VLM ingest
throughput (chunks / sec), LLM summarization latency, storage growth rate.

## Storage

Video corpus size + vector / graph DB indices are the dominant storage cost.
Size against the retention window:

- **Local disk** — fastest, suitable for S-tier evaluations.
- **NAS / NFS** — recommended for M / L tiers with shared corpora.
- **S3-compatible object store** — supported by upstream VSS via
  environment configuration; recommended for large / long-retention
  archives.

Actual GB / hour of video depends on your footage (depends on bitrate,
resolution, container). Measure early; document per-site. Index size is
typically 5–15 % of raw video size for typical embedding schemes.

## Data handling

Video at rest may be sensitive (PII, security-camera footage, medical
imaging). Document upfront:

- Retention window.
- Encryption at rest (Docker volume encryption, filesystem-level, or
  hardware-level).
- Access-control (who can query VSS, who can retrieve raw clips).
- Deletion / audit trail.

## Lifecycle

| Operation | How |
|-----------|-----|
| **Update VSS Blueprint** | `git fetch` in the VSS repo, check out the new tag, restart via `dev-profile.sh`. |
| **Update the LLM or VLM** | Change the model tag in the vLLM `docker run`, restart the container. |
| **Rollback** | `dev-profile.sh down` + `docker rm -f` the vLLM containers; redeploy previous versions. |
| **Re-index a corpus** | Restart VSS with the same corpus path — VSS re-processes as needed. |

## Common issues

| Symptom | Fix |
|---------|-----|
| NGC image pull fails | Confirm Docker version is `28.3.3 ≤ version < 29.5.0`. |
| VLM container OOM at startup | Start VLM **before** LLM; vLLM needs free GPU at startup. |
| Deploy passes bad `-H` flag silently | `dev-profile.sh` exits on unknown host profiles — verify the `-H` argument matches the platform (`RTXPRO6000BW`, `DGX-SPARK`, …). |
| Long TTFT at c8 on T2 | Prefer c2–c4 for interactive workloads on the S tier. |
| NVFP4 MoE errors on public images | Pin the Marlin backend (`--moe-backend marlin` + `VLLM_NVFP4_GEMM_BACKEND=marlin`) as the Lightning recipes do. |
| Camera capacity exceeded | Move to a larger YOLO26 variant, add a GPU (M tier), or downsample the camera ingest rate. |

## Related

- [Solution overview](README.md) — sizing, benchmarks.
- [Developer Deploy Guide](deploy-guide-dev.md) — developer / single-host flow.
- [Recipe catalog](../../recipes/README.md) — standalone serving recipes.
- [Sizing reference](../../docs/sizing.md) — tier memory and platform naming.
- [Upstream VSS Blueprint](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization).
