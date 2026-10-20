# Inference Stack & Models

The single source of truth mapping **serving stack → model → system tier →
expected performance** for solutions. Defaults are opinionated; alternatives are
provided as reference.

## Inference serving

| Stack | Role | When to use |
|-------|------|-------------|
| **[vLLM](https://github.com/vllm-project/vllm)** | **Preferred / production** | First and best for production, multi-session deployments; OpenAI-compatible API; the default for all solutions and all benchmarks |
| Ollama | Reference / quick-start | Developer quick-start, single-user experimentation |
| NVIDIA NIM | Containerized microservice | Standardized, reproducible packaging; enterprise support |
| TensorRT-LLM | High-performance | Maximum throughput on specific NVIDIA silicon |
| SGLang | Alternative | Low-concurrency, deep agentic AI session serving in production; structured generation |
| llama.cpp | Lightweight / GGUF | CPU-assisted or low-footprint deployments |

All solutions standardize their **benchmarks** on vLLM via the aiperf harness so
S/M/L numbers are comparable.

## Models

| Role | Model | License |
|------|-------|---------|
| **Default · S** | **[Nemotron 3.5 Lightning NVFP4](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4)** (`nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4`; served aliases e.g. `nvidia/nemotron-3.5-lightning`) | [OpenMDW-1.1](https://openmdw.ai/license/1-1/) |
| **Default · M/L** | **[Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4) NVFP4** (`nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4`) — recipes in `recipes/{precision,gb300}/vllm/`; Lightning is the measured alternative | [OpenMDW-1.1](https://openmdw.ai/license/1-1/) |
| Alternative · S (GB10) | **[Qwen3.8 27B NVFP4](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4)** (MTP spec-decode baked in) | [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0) |
| Alternative · M | **[Qwen3.8-Flash-Next NVFP4](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4)** (125B/6B-active MoE, MTP ×3, engram CPU offload) | [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) |
| Alternative · L (GB300) | **[GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) NVFP4** (320B/18B-active MoE, 262K ctx) | [MIT](https://opensource.org/license/mit) |
| State-of-the-art reference | GLM, Qwen, Llama, plus latest open weights | per model card |

Licenses are those published on each model card; weights are downloaded from Hugging Face and not redistributed by this repository.

Refreshed as new open-weight coding models are released. Last updated 10/16/2026.

### Per-tier shipping pick (measured)

| Tier | Shipping model | Why (measured) |
|------|----------------|----------------|
| **S · GB10** | Lightning NVFP4 | Highest agent-workflow load among fits (~66 tok/s); agentic eval 100%; tool-calling eval 89%. |
| **S · T2** | Lightning NVFP4 | Lightning 5,352 / 399 (chat / agent tok/s). |
| **M · T4** | Nemotron 3.5 Super VL | Super VL on one TP=2 instance (2 GPUs): agent shape 168 tok/s aggregate at c32, ≥20 tok/s/session to about 6 concurrent sessions; chat 1,814 tok/s at c64 (TP=2 measured on a T6 host — the same RTX PRO 6000 Max-Q pairing as the T4). Lightning reference: agentic eval 100%. |
| **L · T6** | Nemotron 3.5 Super VL | Super VL as 2 × TP=2 replicas behind LiteLLM (4 GPUs): agent shape 252 tok/s at c32 (1.5× a single TP=2 instance), ≥20 tok/s/session to about 11 concurrent sessions; chat 2,020 tok/s at c64. Lightning reference: agentic eval 100% (1 GPU). |
| **L · GB300** | Nemotron 3.5 Super VL | Super VL single instance: agent shape 225 tok/s at c32, ≥20 tok/s/session to about 10 concurrent sessions; chat 3,694 tok/s at c64. Lightning reference: agentic eval 100%; agent-workflow load ~335 @ c20; ≥20 tok/s per session up to ~17 concurrent sessions (measured ladder). L-tier alt GLM-5.3-Flash NVFP4 serving-verified (~111 out tok/s single-stream spot check). |

## Containers & orchestration

- **Containers:** NVIDIA NIM, [Docker](https://www.docker.com/) / Podman (container-first; ~90% of GB10 use
  cases are containerized).
- **Orchestration:** Docker Compose (single node), Kubernetes (optional, larger
  scale / app-host tier).

## OS coverage

| OS | Systems |
|----|---------|
| DGX OS (Ubuntu-based Linux) | Dell Pro Precision with GB10 |
| Ubuntu 24.04+ | Dell Pro Precision with GB300, Precision Towers |

## Management environment

- Enterprise identity (AD/LDAP) integration — primary in ~50% of GB10 use cases.
- Fleet deployment & monitoring ([Prometheus](https://prometheus.io/)/[Grafana](https://grafana.com/) reference).
- Dev→prod scaling patterns documented per solution.
