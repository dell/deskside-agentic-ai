# Agentic Coding — IT-Admin Deployment Guide

Runbook for deploying and operating the Agentic Coding template on a Dell deskside
system.
For fleet-wide rollouts across enrolled machines, see
[Fleet Deploy via Landscape](landscape-fleet-deploy.md).

**Target:** a new admin reaches a working, verified endpoint in **< 60 minutes**
(warm cache) following this guide end-to-end.

## 0. Prerequisites

| Item | GB10 (S) | T2 (S) | T4 (M) | T6 (L) | GB300 (L) |
|------|----------|--------|--------|--------|-----------|
| OS | DGX OS (Ubuntu) | Ubuntu 24.04 | Ubuntu 24.04 | Ubuntu 24.04 | Ubuntu 24.04 |
| NVIDIA driver | Pre-installed | >= 570 | >= 570 | >= 570 | Pre-installed |
| CUDA | Pre-installed | >= 12.x | >= 12.x | >= 12.x | Pre-installed |
| Container runtime | [Docker](https://www.docker.com/) | Docker (rootless OK) | Docker (rootless OK) | Docker (rootless OK) | Docker |
| HF model cache | `~/.cache/huggingface` | same | same | same | same |
| Disk (model) | ~21 GB (Lightning) | ~21 GB | ~62 GB (Super VL) | ~62 GB (Super VL) | ~62 GB (Super VL) – ~181 GB ([GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4)) |
| Network | Outbound HTTPS for first model pull (or pre-seed cache for air-gapped) | same | same | same | same |

### Prerequisite checks

Run all checks before deploying. Every command must pass.

```bash
# 1. OS version
cat /etc/os-release | grep VERSION_ID
# Expected: 24.04 or later

# 2. NVIDIA driver
nvidia-smi --query-gpu=driver_version --format=csv,noheader
# Expected: 570.x or later

# 3. GPU(s) detected
nvidia-smi --query-gpu=name --format=csv,noheader
# Expected: at least one NVIDIA GPU. (memory.total reports N/A on GB10 unified memory;
# there use: free -g   -> >= 100 GiB total. Discrete GPUs: add memory.total, >= 24 GB.)

# 4. Docker + NVIDIA runtime
docker --version
docker info 2>/dev/null | grep -i nvidia
# Expected: Docker 24+ with nvidia runtime

# 5. NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
# Expected: GPU table displayed inside container

# 6. Disk space for model weights
df -h ~/.cache/huggingface --output=avail 2>/dev/null || df -h /home --output=avail
# Expected: >= 25 GB free (S/M) or >= 70 GB free (L)
```

If any check fails, see [Troubleshooting](#troubleshooting) at the end of this guide.

## 1. Pre-seed the model (recommended for air-gapped / fleet)

```bash
# On a connected host, warm the HF cache, then sync ~/.cache/huggingface to fleet nodes
huggingface-cli download nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4

# Verify the download (~21 GB)
du -sh ~/.cache/huggingface/hub/models--nvidia--NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4/
```

For air-gapped environments, copy the cache to each target host:

```bash
rsync -avP ~/.cache/huggingface/ admin@<target-host>:~/.cache/huggingface/
```

## 2. Deploy

Every recipe serves on **port 8000** (the first free port counting up from 8000; `DESKSIDE_BASE_PORT` or `--port`
override), pulls the pinned image, and returns only when the endpoint is ready. The **Recipe Configuration** panel at the top
of this page fills the commands below for your platform, model, host, port and key.

| Platform | Tier | Models (recipe directory) |
|----------|------|---------------------------|
| Dell Pro Precision with GB10 (DGX Spark class device) | S | [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4) (default) · [Qwen3.8-27B](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4) — `gb10` |
| Dell Pro Precision 9 T2 (1× RTX PRO 6000) | S | Nemotron 3.5 Lightning (default) · Qwen3.8-27B (`gb10` recipe with a GPU pin) — `precision` |
| Dell Pro Precision 9 T4 (2× RTX PRO 6000) | M | [Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4) (default) · Nemotron 3.5 Lightning · [Qwen3.8-Flash-Next](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4) · Qwen3.8-27B (`gb10` recipe, GPU-pinned) — `precision` |
| Dell Pro Precision 9 T6 (5× RTX PRO 6000) | L | Nemotron 3.5 Super VL (default) · Nemotron 3.5 Lightning · Qwen3.8-Flash-Next · Qwen3.8-27B (`gb10` recipe, GPU-pinned) — `precision` |
| Dell Pro Precision with GB300 (DGX Station class device) | L | Nemotron 3.5 Super VL (default) · Nemotron 3.5 Lightning · [GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) · Qwen3.8-Flash-Next (`precision` recipe) · Qwen3.8-27B (`gb10` recipe, GPU-pinned) — `gb300` |

### GB10 (S)

```bash
recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000   # default
recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh --port 8000              # alternative
```

### Precision T2 (S, x86)

```bash
recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
```

The recipe bakes the Blackwell (RTX PRO 6000) reference config: FP8 KV
cache, 0.9 GPU memory utilization, 200K context, and 512 concurrent
sequences (cudagraph capture sized to match). Tunables: `--tp N`
(auto-detects GPUs), `--max-model-len`, `--max-num-seqs`, `NEMOTRON_LIGHTNING_GPU_MEM_UTIL`. For air-gapped
towers, point `NEMOTRON_LIGHTNING_DIR=/path/to/checkpoint` at a pre-copied
checkpoint (no [Hugging Face](https://huggingface.co/) pull); on rootless-Docker towers set
`NEMOTRON_LIGHTNING_ROOTLESS=1`.

### Precision T4 (M) and T6 (L) — topology is chosen per workload

TP (one instance across GPUs) vs data-parallel (replicas behind a router) is decided **by measurement for your
workload**, not by rule — see [topology](../../docs/topology.md). Both paths use the same recipes:

```bash
# default model, one instance (TP auto-snaps to a power of two <= GPU count; T4 -> TP=2)
recipes/precision/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh --port 8000
#    PCIe-only towers: TP>1 crashes vLLM's custom all-reduce unless you set NEMOTRON_35_SUPER_VL_DISABLE_CUSTOM_AR=1

# alternatives on the same hardware
recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
recipes/precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh --port 8000

# data-parallel: N replicas pinned one per GPU + LiteLLM front door on :8000 (replicas :8001..; front door always keyed)
recipes/lib/launch-replicas.sh --recipe recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh \
    --env-prefix NEMOTRON_LIGHTNING --served nvidia/nemotron-3.5-lightning --replicas 5     # T6
```

### GB300 (L)

```bash
recipes/gb300/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh --port 8000   # default
recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000  # Lightning
recipes/gb300/vllm/docker-glm-5.3-flash-nvfp4.sh --port 8000           # alternative
```

Running two recipes on one GB300 puts the second on the next free port (8001, …); give each its own
`--gpu-mem-util`.

The recipe pulls the [vLLM](https://github.com/vllm-project/vllm) image, starts a detached container, and serves the
model. Wait for readiness:

```bash
until curl -sf http://localhost:8000/v1/models >/dev/null; do sleep 5; done
curl -s http://localhost:8000/v1/models | python3 -m json.tool
```

**Expected time:** < 5 minutes from `docker run` to `/v1/models` responding
(warm cache). First-time model download adds 10-30 minutes depending on
network speed.

## 3. Verification checklist

Run every check below. All must pass before declaring the deployment operational.

```bash
# --- A. Model endpoint ---
# A1. Model is listed
curl -sf http://localhost:8000/v1/models | python3 -c "
import sys, json
models = json.load(sys.stdin)['data']
print(f'Models loaded: {len(models)}')
for m in models: print(f'  - {m[\"id\"]}')
assert len(models) > 0, 'No models loaded'
"

# A2. Chat completion works (smoke test)
curl -sf http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "nvidia/nemotron-3.5-lightning",
    "messages": [{"role":"user","content":"Write a Python function to reverse a string."}],
    "max_tokens": 512
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(r['choices'][0]['message']['content'][:200])
assert r['choices'][0]['finish_reason'] in ('stop','length'), 'Unexpected finish reason'
print('PASS: chat completion works')
"
# Note: Nemotron 3.5 Lightning is a reasoning model — budgets below ~500
# tokens are consumed entirely by the thinking trace (empty content,
# finish_reason=length). Give clients >= 512.

# --- B. GPU health ---
# B1. GPU utilization is non-zero (during/after inference)
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
  --format=csv
# Expected (discrete GPUs): memory.used > 15 GB (model loaded), temp < 85C
# GB10: memory.used is N/A -- check the container instead:  docker stats --no-stream <container>
#       and  nvidia-smi --query-compute-apps=pid,process_name --format=csv   (the vLLM process is listed)

# --- C. Container health ---
# C1. Container is running. Names: GB10 lightning-3.5-gb10 | Precision lightning-3.5-precision-<port>
#     | GB300 vllm_<port>   (ports count up from 8000; see docs/operations.md)
docker ps --filter name=lightning-3.5 --filter name=vllm_ --format "{{.Names}} {{.Status}}"
# Expected: "<name>  Up X minutes"
# Or skip A-D and run the per-recipe health assessment (exit 1 on any FAIL, --json available):
#   recipes/<platform>/vllm/health-nemotron-3.5-lightning-nvfp4.sh

# C2. No errors in recent logs
docker logs --tail 50 lightning-3.5-gb10 2>&1 | grep -iE "error|exception|traceback" || echo "PASS: no errors in logs"

# C3. Restart policy baked in (boot-resume, locked to the pinned model)
docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' lightning-3.5-gb10
# Expected: unless-stopped

# --- D. Metrics endpoint ---
# D1. vLLM Prometheus metrics are available
curl -sf http://localhost:8000/metrics | head -5
# Expected: lines starting with # HELP or vllm_*
```

If any check fails, see [Troubleshooting](#troubleshooting) below.

## 4. Monitoring (Prometheus + Grafana)

### Prometheus scrape config

Add the vLLM endpoint to your [Prometheus](https://prometheus.io/) `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'vllm-agentic-coding'
    scrape_interval: 15s
    static_configs:
      - targets: ['<deskside-host>:8000']
        labels:
          tier: 'S'
          model: 'nemotron-lightning'
          host: 'deskside-s1'
```

### Key metrics to monitor

Every recipe starts the shared tokenomics Prometheus + Grafana for you (`monitoring/README.md`); the alert rules below are
shipped in `monitoring/alerts.yml` (unit-tested with `promtool`). Bring-your-own Prometheus: copy the scrape job and rules.

| Signal | PromQL | Alert (shipped rule) |
|--------|--------|----------------------|
| Output tok/s | `sum(rate(vllm:generation_tokens_total[1m]))` | per-session < 10 tok/s while busy for 10 m (`DesksidePerSessionBelowFloor`) |
| TTFT p95 | `histogram_quantile(0.95, sum by (le)(rate(vllm:time_to_first_token_seconds_bucket[5m])))` | > 2 s for 10 m (`DesksideTTFTHigh`) |
| Waiting requests | `vllm:num_requests_waiting` | > 0 for 5 m = capacity exceeded (`DesksideQueueBuilding`) |
| KV cache | `vllm:kv_cache_usage_perc` | > 90 % for 5 m (`DesksideKVCacheHigh`) |
| Target down | `up{job="deskside-vllm"}` | == 0 for 2 m (`DesksideTargetDown`) |
| GPU memory (discrete GPUs only) | `DCGM_FI_DEV_FB_USED` (dcgm-exporter) | > 90 % of total; **not available on GB10** (unified memory) -- use node memory |

*Running requests* is capped by `--max-num-seqs`, so "running > max-num-seqs" can never fire; alert on **waiting** instead.

### Grafana dashboard

The **Deskside Tokenomics** dashboard is provisioned automatically (uid `deskside-tokenomics`): tokens served,
cloud-equivalent spend vs amortised on-prem cost, $ per 1M output tokens, platform utilisation, per-session tok/s vs
the floor, TTFT/ITL, prefix-cache hit rate, KV usage, queue depth. The recipe prints the URL (Grafana moves to the next
free port if 3000 is taken) and the admin-password file. It reads only vLLM counters/gauges — no prompts or completions.
Cost inputs are assumptions you edit in the dashboard header. GPU-health panels need dcgm-exporter (not provided).

## 5. Identity & access control

> By default a recipe publishes the endpoint on all interfaces without authentication (and prints a warning).
> Restrict it with `--bind 127.0.0.1` (or a specific address), require a key with `DESKSIDE_API_KEY` /
> `--api-key-file` (enforced by vLLM via `VLLM_API_KEY`), or front it with the LiteLLM gateway, which is always keyed.
> Terminate TLS and apply identity, per-user keys and rate limits in your own gateway.

Do **not** expose `:8000` directly to end users. Front it with a reverse proxy or
API gateway that enforces authentication:

| Approach | When to use | Setup |
|----------|-------------|-------|
| **Nginx reverse proxy** | Single-user or small team | `proxy_pass http://localhost:8000;` with basic auth or mTLS |
| **API gateway (Kong / Envoy)** | Enterprise, multi-user | AD/LDAP integration, API key management, rate limiting |
| **[LiteLLM](https://www.litellm.ai/) proxy** | Multi-model, load balancing | Built-in key management |

The recipes start the serving containers with `--restart unless-stopped`: the
deployed stack fully resumes on boot, locked to the recipe's pinned model and
serving flags. Apply the same policy to the monitoring/gateway containers
(Prometheus, Grafana, LiteLLM/Nginx) so the whole stack comes back unattended.
To keep a node down through a maintenance window:

```bash
docker update --restart=no lightning-3.5-gb10   # restore: --restart=unless-stopped
```

## 6. Lifecycle management

- **Upgrade:** pull the new vLLM image tag and re-run the recipe.
  The recipe removes the old container automatically.
- **Boot resume:** every recipe runs `docker run --restart unless-stopped`, so a
  reboot (or docker daemon restart) brings the serving container back
  automatically with the pinned model — no re-deploy. Verify with the check in
  §3C. (Manual containers started without the policy must be opted in via
  `docker update --restart=unless-stopped <container>`.)
- **Rollback:** re-run the recipe with the previous image tag
  (`NEMOTRON_LIGHTNING_IMAGE=<old-tag> recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh`).
- **Log rotation:** configure via Docker daemon (`max-size`, `max-file`) or
  use `docker logs --since` for bounded queries.
- **Backup:** the only stateful data is the HF model cache (`~/.cache/huggingface`).
  Back it up for air-gapped recovery.

## 7. Scale (dev → prod)

| From | To | Trigger (measured) | How |
|------|----|-------------------|-----|
| Single dev (**S**) | Small team (**M**, T4) | TTFT p95 > 1 s at your concurrent user count | TP=2 on T4 (2 GPUs); gateway for round-robin if running 2 instances |
| Team (**M**) | App host (**L**, GB300/T6) | TTFT p95 > 2 s at M-tier, or > 8 concurrent devs | Multi-instance on T6 (1 vLLM per GPU, LiteLLM proxy) or single instance on GB300 |

**Measured scaling for your configuration.** Pick a platform and model in **Recipe Configuration** at the top of this page; the table
below shows the aiperf results measured for that exact combination (source: `tests/data/`). Rows in amber are below the 20 tok/s
per-session responsiveness floor. The table reports measured concurrency directly; turning sessions into seats is a team-shape
planning call for your pilot, not a measured figure.

<div class="ds-measured"><p>Select a platform and model in Recipe Configuration to see measured scaling here.</p></div>

**Rule of thumb:** move to the next tier when your sustained concurrent user count
causes TTFT p95 > 1 second or the waiting-requests queue is non-empty.

Right-size with measured data — run the aiperf sweep per tier (see the template
[Validation](README.md#validation-aiperf)) and pick the instance count that holds
your target TTFT at peak concurrency.

## 8. Security & isolation

### Network exposure audit

```bash
# Verify only expected ports are open
ss -tlnp | grep -E ':(8000|9090|3000)\b'
# Expected: 8000 (vLLM), 9090 (Prometheus), 3000 (Grafana — container default)
# No other services should be listening externally. SSH (22) is not part of
# this solution's footprint — host administration policy is yours to set, and
# fleet serving-recipe rollouts run without SSH (see landscape-fleet-deploy.md).
```

### Secrets management

- Never commit HuggingFace tokens, API keys, or credentials to the repository.
- Use environment variables or a secrets manager for tokens.
- The vLLM endpoint does not require an API key by default; add one via the
  gateway/proxy layer.

### Docker socket

- Do **not** expose the Docker socket to non-root users in production.
- Use rootless Docker on Precision towers (T2/T4/T6) where supported.

## 9. Teardown

```bash
docker rm -f lightning-3.5-gb10
# Optionally remove the model cache (root-owned blobs if the container
# downloaded as root — use sudo):
# sudo rm -rf ~/.cache/huggingface/hub/models--nvidia--NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4/
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `nvidia-smi` not found | NVIDIA driver not installed | Install driver: `sudo apt install nvidia-driver-570` (Ubuntu) or reinstall DGX OS |
| Docker `nvidia` runtime missing | NVIDIA Container Toolkit not installed | `sudo apt install nvidia-container-toolkit && sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker` |
| Container exits immediately | OOM or model too large for GPU | Check `docker logs lightning-3.5-gb10`; reduce `--gpu-memory-utilization` to 0.6 or use a smaller model |
| `Free memory on device cuda:0 ... is less than desired GPU memory utilization` at startup | GB10 unified memory already held by other processes (a local ollama/llama-server, leftover benchmark workers — CPU RAM and GPU memory are the same pool) | `nvidia-smi` process list to find squatters (`--query-gpu=memory.used` reports N/A on GB10); stop them, or run with `--gpu-memory-utilization` sized to the free pool |
| `curl /v1/models` returns connection refused | Container still starting / crashed | Wait up to 5 min; check `docker ps` and `docker logs` |
| 500 errors under concurrency | MoE backend instability | Ensure `--moe-backend marlin` is set (default in the GB10/Precision Lightning recipes); reduce `--max-num-seqs` |
| Slow TTFT (> 2 s) | Too many concurrent users for tier | Check `vllm:num_requests_waiting` metric; scale to next tier |
| Permission denied (rootless Docker) | `--ulimit memlock=-1` not supported | Use the Precision recipe (`recipes/precision/`) which drops this flag |
| Model download hangs | Network/firewall blocking HuggingFace | Pre-seed the cache (Section 1) or configure `HF_HUB_OFFLINE=1` |
| GPU temperature > 85 C | Sustained load without cooling | Check airflow; reduce `--max-num-seqs` to limit concurrency |
