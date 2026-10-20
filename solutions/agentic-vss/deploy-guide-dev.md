# Agentic VSS — Developer Quick-Start

> **Who this is for:** developers standing up the VSS Blueprint on a single
> Dell deskside system for evaluation or a small deployment.
>
> **IT fleet path:** [IT-Admin Guide](it-admin-guide.md).

## Prerequisites

- Ubuntu 24.04 LTS or newer on Dell Pro Precision 9 towers and Dell Pro Precision with GB300; GB10 systems ship with DGX OS.
- [Docker](https://www.docker.com/) CE `28.3.3 ≤ version < 29.5.0` (upstream VSS is sensitive to
  Docker versions — 29.5.0+ may fail pulling NGC images).
- NVIDIA Container Toolkit.
- Git LFS.
- **NGC API key** (`NGC_CLI_API_KEY`) — VSS pulls NGC-hosted images.
- **[Hugging Face](https://huggingface.co/) token** (`HF_TOKEN`) with access to the Nemotron models.
- Enough disk for the VSS containers + LLM + VLM weights (~50–80 GB).

## 1) Clone the upstream VSS blueprint

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization.git
cd video-search-and-summarization
git checkout tags/v3.2.0
git lfs install && git lfs pull
```

## 2) Set credentials

```bash
export NGC_CLI_API_KEY='<your NGC key>'
export HF_TOKEN='hf_<your HF token>'
```

## 3) Stand up the local vLLM servers

Both the LLM and VLM run as local [vLLM](https://github.com/vllm-project/vllm) containers on the same GPU
(S-tier co-location). **Startup order matters: start the VLM container
before the LLM container** — vLLM requires the target GPU to have free
memory at startup.

### S — Dell Pro Precision with GB10 (128 GB unified) · Dell Pro Precision 9 T2 (96 GB)

LLM default on both S-tier systems is
`nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4`. The S-tier
alternative (`nvidia/Qwen3.8-27B-NVFP4`) uses the same shape with its own
serving flags — see the recipe below.

```bash
# VLM server — Nemotron 3 Nano Omni (inline command)
docker run -d --name vllm-vlm \
  --gpus all -p 30082:8000 -e HF_TOKEN=$HF_TOKEN \
  vllm/vllm-openai@sha256:cb9bc64f0f038c2c2ebf13b31248fb87aca40c356c3d20f363be087cfcff1fcd \
  --model nvidia/nemotron-3-nano-omni-30b-a3b \
  --tensor-parallel-size 1 --gpu-memory-utilization 0.35 --max-model-len 8192 \
  --trust-remote-code

# LLM server — Nemotron 3.5 Lightning 30B A3B NVFP4 (start AFTER the VLM)
docker run -d --name vllm-llm \
  --gpus all -p 30081:8000 -e HF_TOKEN=$HF_TOKEN \
  -e VLLM_NVFP4_GEMM_BACKEND=marlin \
  vllm/vllm-openai@sha256:cb9bc64f0f038c2c2ebf13b31248fb87aca40c356c3d20f363be087cfcff1fcd \
  --model nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 \
  --moe-backend marlin --kv-cache-dtype fp8 \
  --tensor-parallel-size 1 --gpu-memory-utilization 0.35 --max-model-len 8192
```

Notes:

- `--gpu-memory-utilization 0.35` for **each** container is the validated
  co-location budget on a 96 GB T2 (peak combined use **68.3 GB of 96 GB**,
  measured). On GB10 unified memory, size the two containers against the
  free pool the same way.
- The `nightly` image and the Marlin backend pins are what the shipping
  Lightning recipes use (older public-image tags fail Lightning weight
  load).
- To serve the same model **standalone** (outside VSS, full GPU), use the
  repo recipes instead:
  `recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh` (GB10)
  or `recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh`
  (Precision T2) — they bake full-utilization configs, not the 0.35
  co-location cap.
- The measured S-tier concurrency sweeps in the
  [README](README.md#benchmarks-performance-validation) were run with the
  prior reference models; re-run your sweep after swapping the lineup.

### M / L tiers

M (Dell Pro Precision 9 T4, RTX PRO 6000 servers) and L (Dell Pro Precision with
GB300, 252 GB HBM3e) follow the same flow with the tier's model at TP or
multi-instance (see the [README sizing table](README.md#s-m-l-sizing)).

## 4) Verify the vLLM endpoints

```bash
export LLM_ENDPOINT_URL=http://localhost:30081/v1
export VLM_ENDPOINT_URL=http://localhost:30082/v1

curl -s $LLM_ENDPOINT_URL/models
curl -s $VLM_ENDPOINT_URL/models
```

Both should list the model loaded above.

## 5) Deploy VSS (Standard hybrid mode, `base` profile)

### Dell Pro Precision with GB10

```bash
deploy/docker/scripts/dev-profile.sh up -p base -H DGX-SPARK \
  --use-remote-llm --use-remote-vlm \
  --llm nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 \
  --vlm nvidia/nemotron-3-nano-omni-30b-a3b
```

### Dell Pro Precision 9 T2

```bash
deploy/docker/scripts/dev-profile.sh up -p base -H RTXPRO6000BW \
  --use-remote-llm --use-remote-vlm \
  --llm nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 \
  --vlm nvidia/nemotron-3-nano-omni-30b-a3b
```

## 6) Verify VSS

```bash
curl -I http://localhost:7777       # VSS Agent UI - expect HTTP 200
curl -fsS http://localhost:8000/health
```

Open `http://localhost:7777` in a browser to reach the VSS Agent UI. Try a
natural-language query against a sample clip to confirm the end-to-end path
(ingest → embed → search → summarize).

## Rollback

```bash
deploy/docker/scripts/dev-profile.sh down
docker rm -f vllm-llm vllm-vlm
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| VSS deploy fails pulling NGC images | Confirm Docker version is `28.3.3 ≤ version < 29.5.0`. Newer Docker versions can fail on NGC pulls. |
| vLLM container OOM at startup | Start the VLM container **before** the LLM. vLLM requires free GPU at startup. |
| Long TTFT at concurrency 8 on T2 | Prefer concurrency 2–4 for interactive workloads on T2 — see the [Benchmarks section](README.md#benchmarks-performance-validation). |
| NVFP4 MoE serving errors / instability on public images | Pin the Marlin backend: `--moe-backend marlin` + `VLLM_NVFP4_GEMM_BACKEND=marlin` (defaults in the Lightning recipes). |
| Lightning weights fail to load on an older image | Use the pinned image from `recipes/versions.lock` — older public-image tags reject the Lightning weight layout. |

## Related

- [Solution overview](README.md) — sizing, benchmarks.
- [IT-Admin Guide](it-admin-guide.md) — IT-admin fleet path.
- [Recipe catalog](../../recipes/README.md) — standalone serving recipes.
- [Inference stack](../../docs/stack.md) — why vLLM.
- [Upstream VSS Blueprint](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization).
