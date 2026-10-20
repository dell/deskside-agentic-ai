#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NVIDIA Nemotron 3.5 Lightning 30B A3B (NVFP4) -- GB10 (DGX Spark) recipe
#
# Hardware: NVIDIA GB10 Grace-Blackwell, 128 GB unified memory (aarch64).
# Model   : nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 (NVFP4)
# Role    : Reference default serving recipe on S-tier GB10.
#
#   - Image: vllm/vllm-openai:nightly (aarch64 nightly preferred; fall back to
#   - MoE backend: **marlin** (--moe-backend marlin).
#   - Linear GEMM: Marlin (VLLM_NVFP4_GEMM_BACKEND=marlin) — the sm_121
#     constraint on public images.
#   - --gpu-memory-utilization 0.70, --max-model-len 200000, --max-num-seqs 32,
#     --kv-cache-dtype fp8, --load-format auto, TP=1, port 8000,
#     --restart unless-stopped (boot-resume with the pinned model).
#   - agent-workflow shape (ISL=60k / OSL=1024 / 40 req): ~66 out tok/s @ c20.
#
#
# Usage   : ./docker-nemotron-3.5-lightning-nvfp4.sh [--port PORT]
#                                                    [--gpu-mem-util F]
#                                                    [--max-num-seqs N]
#                                                    [--max-model-len N]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"
IMAGE="${NEMOTRON_LIGHTNING_IMAGE:-$(ds_image lightning)}"
CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-lightning-3.5-gb10}"
PORT="${NEMOTRON_LIGHTNING_PORT:-$(ds_pick_port "${NEMOTRON_LIGHTNING_CONTAINER:-lightning-3.5-gb10}")}"
GPU_MEM_UTIL="${NEMOTRON_LIGHTNING_GPU_MEM_UTIL:-0.70}"
MAX_MODEL_LEN="${NEMOTRON_LIGHTNING_MAX_MODEL_LEN:-200000}"
MAX_NUM_SEQS="${NEMOTRON_LIGHTNING_MAX_NUM_SEQS:-32}"
MOE_BACKEND="${NEMOTRON_LIGHTNING_MOE_BACKEND:-marlin}"
LOAD_FORMAT="${NEMOTRON_LIGHTNING_LOAD_FORMAT:-auto}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; shift 2 ;;
    --gpu-mem-util) GPU_MEM_UTIL="$2"; shift 2 ;;
    --max-num-seqs) MAX_NUM_SEQS="$2"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--port PORT] [--gpu-mem-util F] [--max-num-seqs N] [--max-model-len N]"
      ds_usage_common
      exit 0 ;;
    *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "Unknown option: $1" >&2; exit 3; fi ;;
  esac
done

if [[ "${IMAGE}" == *"/"* ]]; then
  ds_pull "${IMAGE}"
fi
ds_env_args
ds_rm "${CONTAINER}"

# Pass --runtime=nvidia only when the daemon registers that runtime. Hosts
# whose toolkit works through the default-runtime hook alone still get GPUs
# via --gpus; hardcoding the runtime would fail the run there.
ds_runtime_opt

ds_docker run -d --restart unless-stopped \
  ${DS_RUNTIME_OPT[@]+"${DS_RUNTIME_OPT[@]}"} \
  --gpus all \
  --ipc=host \
  --shm-size=8g \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -e VLLM_NVFP4_GEMM_BACKEND=marlin \
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_HOME:-$HOME/.cache/huggingface}:/root/.cache/huggingface" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name nvidia/nemotron-3.5-lightning nemotron-lightning lightning auto \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --tensor-parallel-size 1 \
    --moe-backend "${MOE_BACKEND}" \
    --kv-cache-dtype fp8 \
    --load-format "${LOAD_FORMAT}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser nemotron_v3

echo "Nemotron 3.5 Lightning (GB10) launched on port ${PORT}"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/gb10/vllm/health-nemotron-3.5-lightning-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "nvidia/nemotron-3.5-lightning" "${CONTAINER}"
