#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NVIDIA Nemotron 3.5 Lightning 30B A3B (NVFP4) -- GB300 UUID-pin recipe
#
# Hardware: Dell Pro Precision / DGX Station GB300 (aarch64). The GB300 GPU is
#           UUID-pinned (auto-detected via nvidia-smi; override with env).
# Model   : nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 (NVFP4)
# Role    : Reference default serving recipe on L-tier GB300.
#
#   - Image: vllm/vllm-openai:nightly (**required** — v0.22.0 failed Lightning
#     weight load with vocab/embed size mismatch).
#   - Host port: first free port counting up from 8000 (DESKSIDE_BASE_PORT / --port override), container name vllm_<port>.
#   - --moe-backend marlin + VLLM_NVFP4_GEMM_BACKEND=marlin,
#     --gpu-memory-utilization 0.85, --max-model-len 200000,
#     --max-num-seqs 512, --kv-cache-dtype fp8,
#     --mamba-ssm-cache-dtype float32, --enable-expert-parallel,
#     --attention-backend TRITON_ATTN, --max-cudagraph-capture-size 512.
#     --restart unless-stopped (boot-resume with the pinned model).
#   - agent-workflow shape peak ~335 out tok/s @ c20 (raw ladder: tests/data/20261020_bb8ae93).
#
# Override GPU with NEMOTRON_LIGHTNING_GPU_UUID=GPU-… if auto-detect is wrong.
#
# Usage   : ./docker-nemotron-3.5-lightning-nvfp4.sh [--port PORT]
#                                                    [--gpu-mem-util F]
#                                                    [--max-model-len N]
#                                                    [--max-num-seqs N]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"
IMAGE="${NEMOTRON_LIGHTNING_IMAGE:-$(ds_image lightning)}"
PORT="${NEMOTRON_LIGHTNING_PORT:-$(ds_pick_port "vllm_")}"
CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-vllm_${PORT}}"
GPU_MEM_UTIL="${NEMOTRON_LIGHTNING_GPU_MEM_UTIL:-0.85}"
MAX_MODEL_LEN="${NEMOTRON_LIGHTNING_MAX_MODEL_LEN:-200000}"
MAX_NUM_SEQS="${NEMOTRON_LIGHTNING_MAX_NUM_SEQS:-512}"
MOE_BACKEND="${NEMOTRON_LIGHTNING_MOE_BACKEND:-marlin}"
HF_CACHE="${NEMOTRON_LIGHTNING_HF_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-vllm_${PORT}}"; shift 2 ;;
    --gpu-mem-util) GPU_MEM_UTIL="$2"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="$2"; shift 2 ;;
    --max-num-seqs) MAX_NUM_SEQS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--port PORT] [--gpu-mem-util F] [--max-model-len N] [--max-num-seqs N]"
      ds_usage_common
      exit 0 ;;
    *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "Unknown option: $1" >&2; exit 3; fi ;;
  esac
done

GPU_UUID="${NEMOTRON_LIGHTNING_GPU_UUID:-}"
if [[ -z "${GPU_UUID}" ]]; then
  GPU_UUID=$(nvidia-smi --query-gpu=uuid,name --format=csv,noheader \
    | awk -F', ' '/GB300/{print $1; exit}')
fi
if [[ -z "${GPU_UUID}" ]]; then
  echo "ERROR: no GB300 UUID found. Set NEMOTRON_LIGHTNING_GPU_UUID=GPU-…" >&2
  exit 1
fi

ds_pull "${IMAGE}"
ds_env_args
ds_rm "${CONTAINER}"

ds_docker run -d --restart unless-stopped \
  --gpus "device=${GPU_UUID}" \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -e VLLM_NVFP4_GEMM_BACKEND=marlin \
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_CACHE}:/root/.cache/huggingface" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name nvidia/nemotron-3.5-lightning nemotron-lightning lightning auto \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --kv-cache-dtype fp8 \
    --mamba-ssm-cache-dtype float32 \
    --tensor-parallel-size 1 \
    --moe-backend "${MOE_BACKEND}" \
    --enable-expert-parallel \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --max-cudagraph-capture-size 512 \
    --attention-backend TRITON_ATTN \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser nemotron_v3

echo "Nemotron 3.5 Lightning (GB300 UUID-pin ${GPU_UUID}) launched on port ${PORT}"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/gb300/vllm/health-nemotron-3.5-lightning-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "nvidia/nemotron-3.5-lightning" "${CONTAINER}"
