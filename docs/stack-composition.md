# Stack Composition Standard

Every solution template and reference architecture in this repo is
described as a composition of two layers. This standard makes solutions
comparable, repeatable, and easy to author consistently.

## The two layers

### 1. Dell Hardware

The solutions in this repo run on, and only on, these Dell deskside
systems:

| System | Tier | Role in solutions |
|--------|------|-------------------|
| **Dell Pro Precision with GB10** (DGX Spark class device) | S | Deskside AI appliance — 128 GB unified memory, single-GPU inference, DGX OS |
| **Dell Pro Precision 9 T2** | S | Workstation tower, 1× RTX PRO 6000 Blackwell Workstation Edition (96 GB) |
| **Dell Pro Precision 9 T4** | M | Tower, 2× RTX PRO 6000 Blackwell Max-Q (192 GB) — small team, multi-instance or TP serving |
| **Dell Pro Precision 9 T6** | L | Tower, 5× RTX PRO 6000 Blackwell Max-Q (480 GB) — high-capacity multi-instance inference |
| **Dell Pro Precision with GB300** (DGX Station class device) | L | Deskside AI appliance — 252 GB HBM3e + 496 GB LPDDR5X, aarch64, multi-user / app host |

No other Dell platforms (PowerEdge, laptops, storage) are in scope for
these solution templates. See [S/M/L Sizing](sizing.md) for memory budgets
and model fit per tier.

### 2. Open / NVIDIA / Ecosystem Software

| Component | Role |
|-----------|------|
| [NVIDIA AI Enterprise](https://www.nvidia.com/en-us/data-center/products/ai-enterprise/) (CUDA, cuDNN, TensorRT) | Accelerated runtime & libraries |
| NVIDIA NIM | Inference microservices for production model serving |
| [vLLM](https://github.com/vllm-project/vllm) / llama.cpp / whisper.cpp | OpenAI-compatible inference servers (see `recipes/`) |
| PyTorch, [Hugging Face](https://huggingface.co/), LangChain, LlamaIndex | Frameworks for building AI apps |
| MLflow, Kubeflow, [Prometheus](https://prometheus.io/), [Grafana](https://grafana.com/) | MLOps & observability |

## How to express composition in a solution

Each solution README includes a **Stack Composition** table that names the
specific choice for each layer, for example:

| Layer | Choice for this solution |
|-------|--------------------------|
| Hardware | Dell Pro Precision with GB10 (128 GB unified) |
| Software | vLLM + NVIDIA AI Enterprise; model served via `recipes/gb10/vllm/...` |

## Deployment tiers

| Tier | Where it runs | Typical use |
|------|---------------|-------------|
| **Deskside** | Precision / Dell Pro Precision | Dev, test, low-latency local inference |
| **AI Factory** | PowerEdge + NVIDIA DGX | Training, large-scale inference, model mgmt |
| **Hybrid (Edge + Core)** | Both, orchestrated | Distributed inference, federated learning, hybrid RAG |
