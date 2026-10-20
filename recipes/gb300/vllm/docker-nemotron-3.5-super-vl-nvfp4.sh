#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NVIDIA Nemotron 3.5 Super VL 120B-A12B (NVFP4) -- GB300 UUID-pin recipe
#
# Hardware: Dell Pro Precision with GB300 (aarch64). The GB300 GPU is UUID-pinned
#           (auto-detected; override NEMOTRON_35_SUPER_VL_GPU_UUID=GPU-...).
# Model   : nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4 (~62 GB weights)
# Role    : L-tier DEFAULT model (alt: GLM-5.3-Flash; Lightning stays the measured fallback).
#
# Validated: GB300 (252 GB HBM3e), cold start to READY in ~38 min including weight download and compile.
#           Flags = model-card flags (parsers, mamba/prefix, video) + multi-user knobs from
#           the proven Nemotron-3-Super GB300 recipe (expert parallel, TRITON_ATTN, large
#           cudagraph capture). DFlash spec decoding opt-in (NEMOTRON_35_SUPER_VL_DFLASH=1);
#           the card's max-num-seqs 1 lane is GB10-only.
#   - Image: policy release -> digest -> nightly (recipes/versions.lock, id 'supervl').
#   - Host port: first free port counting up from 8000 (DESKSIDE_BASE_PORT / --port override).
#   - Defaults: util 0.85, ctx 262144, 128 seqs (tunable; lower util when co-hosting).
#
# Usage   : ./docker-nemotron-3.5-super-vl-nvfp4.sh [--port PORT] [--gpu-mem-util F]
#                                                   [--max-model-len N] [--max-num-seqs N]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL="${NEMOTRON_35_SUPER_VL_MODEL:-nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4}"
DRAFT_MODEL="${NEMOTRON_35_SUPER_VL_DRAFT:-nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4-LiLiCorr}"
IMAGE="${NEMOTRON_35_SUPER_VL_IMAGE:-$(ds_image supervl)}"
PORT="${NEMOTRON_35_SUPER_VL_PORT:-$(ds_pick_port "vllm_")}"
CONTAINER="${NEMOTRON_35_SUPER_VL_CONTAINER:-vllm_${PORT}}"
GPU_MEM_UTIL="${NEMOTRON_35_SUPER_VL_GPU_MEM_UTIL:-0.85}"
MAX_MODEL_LEN="${NEMOTRON_35_SUPER_VL_MAXLEN:-262144}"
MAX_NUM_SEQS="${NEMOTRON_35_SUPER_VL_MAX_NUM_SEQS:-128}"
COMPILE_THREADS="${NEMOTRON_35_SUPER_VL_COMPILE_THREADS:-8}"
HF_CACHE="${NEMOTRON_35_SUPER_VL_HF_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; CONTAINER="${NEMOTRON_35_SUPER_VL_CONTAINER:-vllm_${PORT}}"; shift 2 ;;
    --gpu-mem-util) GPU_MEM_UTIL="$2"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="$2"; shift 2 ;;
    --max-num-seqs) MAX_NUM_SEQS="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--port PORT] [--gpu-mem-util F] [--max-model-len N] [--max-num-seqs N]"; ds_usage_common; exit 0 ;;
    *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "Unknown option: $1" >&2; exit 3; fi ;;
  esac
done

GPU_UUID="${NEMOTRON_35_SUPER_VL_GPU_UUID:-}"
if [[ -z "${GPU_UUID}" ]]; then
  GPU_UUID=$(nvidia-smi --query-gpu=uuid,name --format=csv,noheader | awk -F', ' '/GB300/{print $1; exit}')
fi
[[ -n "${GPU_UUID}" ]] || { echo "ERROR: no GB300 UUID found. Set NEMOTRON_35_SUPER_VL_GPU_UUID=GPU-..." >&2; exit 1; }
SPEC=()
if [[ "${NEMOTRON_35_SUPER_VL_DFLASH:-0}" == "1" ]]; then
  SPEC=(--speculative-config.method dflash --speculative-config.model "${DRAFT_MODEL}" --speculative-config.num_speculative_tokens 7)
fi

ds_env_args
ds_rm "${CONTAINER}"
ds_pull "${IMAGE}"

ds_docker run -d --restart unless-stopped \
  --gpus "device=${GPU_UUID}" \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -e TORCHINDUCTOR_COMPILE_THREADS="${COMPILE_THREADS}" -e MAX_JOBS="${COMPILE_THREADS}" \
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_CACHE}:/root/.cache/huggingface" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name nvidia/nemotron-3.5-super-vl nemotron-3.5-super-vl auto \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --tensor-parallel-size 1 \
    --enable-expert-parallel \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --max-cudagraph-capture-size "${MAX_NUM_SEQS}" \
    --max-num-batched-tokens 8192 \
    --attention-backend TRITON_ATTN \
    --mamba-backend flashinfer \
    --mamba-ssm-cache-dtype float16 \
    --enable-mamba-cache-stochastic-rounding \
    --mamba-cache-philox-rounds 5 \
    --enable-mamba-shared-prefix-checkpoint \
    --video-pruning-rate 0.5 \
    --media-io-kwargs '{"video": {"fps": 2, "num_frames": 256}}' \
    --block-size 64 \
    --prefix-match-unit 64 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser nemotron_v3 \
    ${SPEC[@]+"${SPEC[@]}"}

echo "Nemotron 3.5 Super VL (GB300 UUID-pin ${GPU_UUID}) launched on port ${PORT}"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/gb300/vllm/health-nemotron-3.5-super-vl-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "nvidia/nemotron-3.5-super-vl" "${CONTAINER}"
