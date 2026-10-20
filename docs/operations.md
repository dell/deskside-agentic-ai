# Operations reference — ports, co-tenancy, resources, prerequisites, air-gap

## 1. Port map (one scheme)
Serving endpoints use **base port 8000, counting up** (`DESKSIDE_BASE_PORT` overrides the base; `--port`/`<PREFIX>_PORT` pins one).
A recipe takes the first free port ≥ base; re-running a recipe reuses *its own* instance's port.

| What | Port | Notes |
|------|------|-------|
| Client endpoint (single instance, or LiteLLM front door in DP) | **8000** | what every client/IDE guide uses |
| Replica instances behind the front door (`recipes/lib/launch-replicas.sh`) | 8001, 8002, … | bound to 127.0.0.1 |
| Additional recipes on the same host | next free (8001…) | e.g. GLM beside Lightning on a GB300 |
| Prometheus / Grafana (tokenomics) | 9090 / 3000 → next free | printed by the recipe; `health-*.sh` shows them |
| VSS Agent UI / VSS health | 7777 / **8000** | collides with the default endpoint → on a VSS host start recipes with `DESKSIDE_BASE_PORT=8100` |
| VSS-internal vLLMs (dev guide) | 30081 / 30082 | upstream blueprint convention |
| JupyterHub / OpenWebUI (Higher-Ed examples) | 8080 / 3100 | OpenWebUI must not use Grafana's 3000 |

## 2. Co-tenancy matrix (can these share one box?)
| Pair | Verdict |
|------|---------|
| Coding + Hermes/OpenClaw (Plane 1 shared) | **yes** — one vLLM serves both; agent sandboxes are CPU/RAM |
| Coding + VSS | **only with a memory plan**: VSS runs its own LLM + VLM at `--gpu-memory-utilization 0.35` each, so 0.35 + 0.35 + the coding instance must be ≤ 1.0 of the GPU. The GB10 Lightning default is 0.70 → lower it (`--gpu-mem-util 0.25`) or use a second GPU. Use `DESKSIDE_BASE_PORT=8100`. Docker must be in VSS's `28.3.3 ≤ v < 29.5.0` window. |
| Two model recipes on one GPU | memory budgets must sum ≤ 1.0 — see the fit rule in [sizing](sizing.md) |
| Any recipe + tokenomics monitoring | yes (host-network Prometheus/Grafana, ≈ 0.5 GB RAM) |

GB10: GPU and CPU share one 128 GB pool — every co-tenant counts against it.

## 3. Per-recipe resources
| Recipe | Weights on disk | Host RAM | GPU / unified memory used | Cold start (download + load) |
|--------|----------------:|---------:|---------------------------|------------------------------|
| Lightning NVFP4 (gb10/precision/gb300) | ~21 GB | 16 GB+ | util 0.70 (GB10) / 0.9 (towers) / 0.85 (GB300) | 10–30 min first run; < 5 min warm |
| [Qwen3.8-27B](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4) NVFP4 | ~18 GB | 16 GB+ | util 0.9 of 128 GB (tune `QWEN38_27B_GPU_MEM_UTIL`) | like Lightning |
| [Qwen3.8-Flash-Next](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4) NVFP4 | ~68 GiB experts + ~102 GiB engram table in **host RAM** | **≥ 128 GB** | ~34 GiB/GPU at TP=2 | long (≈170 GiB) |
| [GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) NVFP4 (GB300) | ~181 GiB | 32 GB+ | util 0.9 of the GB300's 252 GB HBM3e | long |
| [Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4) NVFP4 (M/L default) | ~62 GB | 32 GB+ | T4 TP=2: ~31 GB/GPU weights; T2 single: tight | not measured |
| Tokenomics monitoring | — | ~0.5 GB | none | seconds |

Container images are 22–26 GB each. Free disk before a first run: weights + image + ~10 GB. Numbers come from recipe headers and
local image sizes, not a fresh measurement.

## 4. Prerequisites matrix
| Item | GB10 (DGX OS) | GB300 | Towers T2/T4/T6 (Ubuntu 24.04+) |
|------|---------------|-------|--------------------------------|
| NVIDIA driver | preinstalled | preinstalled | ≥ 570 documented; RTX PRO 6000 Blackwell may require a newer branch — *verify on hardware* |
| Docker | ≥ 24 (VSS: 28.3.3 ≤ v < 29.5.0) | same | same |
| NVIDIA Container Toolkit | present on DGX OS; on `unknown runtime nvidia` run `scripts/landscape/fix-docker-nvidia-runtime.sh` | same | install `nvidia-container-toolkit` |
| CUDA test image | `nvidia/cuda:12.8.0-base-ubuntu24.04` | same | same |
| Python 3 + curl on the host | required by the recipes' readiness check | | |
| OS | DGX OS | Ubuntu 24.04+ | Ubuntu 24.04+ |

## 5. Air-gapped hosts
1. Connected host (same CPU arch): `scripts/airgap/pack-images.sh save /media/pack` (images, pinned per `recipes/versions.lock`) and
   `huggingface-cli download <model>`, then copy `~/.cache/huggingface` (rsync).
2. Air-gapped host: `scripts/airgap/pack-images.sh load /media/pack`; set `HF_HUB_OFFLINE=1` for the recipe and
   `NEMOTRON_LIGHTNING_DIR=/path/to/checkpoint` (or the matching `*_DIR`) to serve a pre-copied checkpoint.
3. Include the monitoring/LiteLLM ids from `versions.lock` in the save list (monitoring images are pinned in `recipes/lib/monitoring.sh`).
4. NemoClaw installer: fetch once on a connected host with `scripts/nemoclaw/headless-install.sh fetch` (hash-pinned) and carry the file.

## 6. FAQ
* **`host.docker.internal` from an OpenShell sandbox?** Use it as the guides do; on plain Linux Docker the name needs
  `--add-host=host.docker.internal:host-gateway` (whether OpenShell injects it was not verified). A recipe bound to `127.0.0.1`
  is *not* reachable that way — bind `0.0.0.0` or a specific interface.
* **GB10 shows `N/A` for GPU memory.** Expected (unified memory). Use `free -g` and `docker stats`; the health scripts handle it.
* **Which topology on T4/T6?** Decided per workload by measurement — [topology](topology.md).
