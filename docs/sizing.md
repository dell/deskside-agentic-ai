# S / M / L Sizing Framework

The sizing framework maps Dell deskside systems to workload scale. Every solution
offers at least two tiers so you **choose your scale, not your stack**.

## Tier → system mapping

| Tier | Dell system(s) | GPU / memory | Typical scale | OS |
|------|----------------|--------------|---------------|----|
| **S** | **Dell Pro Precision with GB10** · **Dell Pro Precision 9 T2** | GB10 (128 GB unified) · 1× RTX PRO 6000 Blackwell Workstation Edition (96 GB) | Single user / developer | DGX OS · Ubuntu 24.04+ |
| **M** | **Dell Pro Precision 9 T4** | 2× RTX PRO 6000 Blackwell Max-Q (192 GB) | Small team | Ubuntu 24.04+ |
| **L** | **Dell Pro Precision with GB300** · **Dell Pro Precision 9 T6** | GB300 (252 GB HBM3e + 496 GB LPDDR5X) · 5× RTX PRO 6000 Blackwell Max-Q (480 GB) | Multi-user / app host | DGX OS · Ubuntu 24.04+ |

The tiers above are the default sizing. A solution may specialize them where its use case calls for it; for example the Higher Education AI Lab defines its own S/M/L around seats and shared pools (see its README).

## Tier memory budgets (for model fit)

| Tier | Usable memory | Notes |
|------|--------------:|-------|
| S (GB10) | 128 GB unified | Shared CPU+GPU; `--gpu-memory-utilization` carves the GPU share |
| S (T2) | 96 GB GDDR7 | RTX PRO 6000 Blackwell Workstation Edition [600W] |
| M (T4) | 192 GB GDDR7 | 2× RTX PRO 6000 Blackwell Max-Q [300W]; multi-instance or TP=2 |
| L (T6) | 480 GB GDDR7 | 5× RTX PRO 6000 Blackwell Max-Q [300W]; multi-instance or TP |
| L (GB300) | 252 GB + 496 GB | HBM3e / LPDDR5X |


## How to choose a tier (per solution)

A solution's S/M/L rows answer: *for this use case and this user count, which
system, model, quant, and inference config — and what performance to expect?*

| Question | Drives |
|----------|--------|
| How many concurrent users? | Tier (S→single, M→team, L→multi-user) |
| Latency vs. throughput priority? | Model size, quant, concurrency settings |
| Context length needed? | `--max-model-len`, KV cache dtype, memory budget |
| On-prem / air-gapped? | OS, container registry, model caching strategy |

Each sizing table cell carries a **status** — *measured*, *spot-check*, *doc-reported* (raw data not in the repo)
or *retired-model*. The machine-readable record of every number, with provenance, is
[`tests/data/latest/sizing.yaml`](../tests/data/latest/sizing.yaml).

## Model-fit rule (weights, KV cache, headroom)

Use the **checkpoint size on disk** when you have it; otherwise estimate weights as
`params_total × bits/8` with **bf16 = 16, fp8 ≈ 8.5, NVFP4 ≈ 4.5 bits** (4-bit values + block scales; *not* a flat ÷4).
MoE models load **all** experts, so use total — not active — parameters.

```
budget  = memory_gb × gpu_memory_utilization − overhead        # overhead ≈ 3–6 GB (CUDA graphs, activations)
          (GB10: unified pool shared with the OS and every other process — subtract what is already resident)
weights = measured checkpoint GB   (or params_total × bits / 8)
fit     = weights / budget
```

| fit | verdict | action |
|-----|---------|--------|
| ≤ 60 % | comfortable | full context and high concurrency possible |
| 60–85 % | **tight** | cap `--max-model-len` / `--max-num-seqs`, FP8 KV cache; confirm with the vLLM startup lines `GPU KV cache size` / `Maximum concurrency` |
| > 85 % | does not leave usable KV cache | add GPUs (TP), offload (e.g. engram), or pick a smaller model |

KV + Mamba/SSM state need real room, not leftovers: **check `GPU KV cache size` in the server log and divide by
(sessions × context)** before promising concurrency.

Worked examples (budget = memory × util − ~4 GB):

| Model (checkpoint) | System | Budget | Fit | Verdict |
|--------------------|--------|-------:|----:|---------|
| Lightning NVFP4 (~21 GB) | GB10, util 0.70 (128 GB pool) | ~86 GB | 24 % | comfortable |
| Super VL NVFP4 (~62 GB) | T4, TP=2, util 0.9 (192 GB) | ~169 GB | 37 % | comfortable (≈31 GB/GPU) |
| Super VL NVFP4 (~62 GB) | T2 single 96 GB, util 0.9 | ~82 GB | 76 % | **tight** — short context, few sequences |
| Super VL NVFP4 (~62 GB) | GB300, util 0.85 | see note | well under 60 % | comfortable (memory figure approximate) |
| [GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) NVFP4 (~181 GiB ≈ 194 GB) | GB300 252 GB, util 0.9 | ~223 GB | ~87 % | **over the line** — works only with FP8 KV and ~45 GB left for KV (the recipe ships it; treat as exceptional) |

The previous "weights ≤ 60 % of budget, NVFP4 = bf16 ÷ 4" rule contradicted the shipped GLM and Flash-Next recipes; this
table is the corrected rule.

## Precision tower coverage

Dell Pro Precision 9 T2/T4/T6 (RTX PRO discrete GPUs) are covered at the solution level by the `precision` recipes
(Lightning, [Qwen3.8-Flash-Next](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4), [Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4)), health wrappers and the DP/TP launcher
([topology](topology.md)). **Measured** tower numbers cover T2, a T4-equivalent TP=2 pair and a T6 2 × TP=2 layout (see `sizing.yaml`).
NVIDIA's Spark/Station/RTX playbooks remain the upstream references.

## Validation platforms

| Tier | Platform |
|------|----------|
| S | Dell Pro Precision with GB10; Dell Pro Precision 9 T2 |
| M | Dell Pro Precision 9 T4 |
| L | Dell Pro Precision with GB300; Dell Pro Precision 9 T6 |
