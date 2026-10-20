#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NVIDIA Nemotron 3.5 Super VL 120B-A12B (NVFP4) -- Dell Precision (x86) recipe
#
# Hardware: Dell Pro Precision 9 T4 (2x RTX PRO 6000, M-tier default) and T6 (L tier,
#           TP/DP per workload -- see docs/topology.md). A single 96 GB T2 is TIGHT
#           (weights ~62 GB = ~72 % of the 0.9 budget): use a short context there.
# Model   : nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4 (modelopt mixed NVFP4,
#           text+image+video -> text, hybrid Mamba+MoE, ~62 GB weights)
# Role    : M/L-tier DEFAULT model (S tier stays Nemotron 3.5 Lightning).
#
# Validated: T6 pair (TP=2) and 2 replicas x TP=2 on RTX PRO 6000 Max-Q. Flags = the NVIDIA model-card serve flags as
#           reproduced in the inference-recipes GB10 lane (parsers, mamba/prefix flags,
#           video options) + multi-user knobs borrowed from the proven Nemotron-3-Super
#           Blackwell recipe (TP=2, expert parallel, large max-num-seqs). The card's
#           GB10 lane (max-num-seqs 1 + DFlash) is NOT a multi-user config, so DFlash
#           speculative decoding is opt-in here (NEMOTRON_35_SUPER_VL_DFLASH=1).
#           Capacity numbers: pending measurement (tests/aiperf).
#   - Image: policy release -> digest -> nightly (recipes/versions.lock, id 'supervl').
#   - TP auto-snaps to a power of two <= GPU count; set NEMOTRON_35_SUPER_VL_GPUS='device=0,1'
#     + NEMOTRON_35_SUPER_VL_TP=2 for multi-instance (lib/launch-replicas.sh does this).
#   - PCIe-only GPU pairs: NEMOTRON_35_SUPER_VL_DISABLE_CUSTOM_AR=1 for TP>1.
#   - Context 200000 at every TP (the agentic-coding per-session standard);
#
# Usage   : ./docker-nemotron-3.5-super-vl-nvfp4.sh [--port PORT] [--tp N] [--gpu-mem-util F]
#                                                   [--max-model-len N] [--max-num-seqs N]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL="${NEMOTRON_35_SUPER_VL_MODEL:-nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4}"
DRAFT_MODEL="${NEMOTRON_35_SUPER_VL_DRAFT:-nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4-LiLiCorr}"
IMAGE="${NEMOTRON_35_SUPER_VL_IMAGE:-$(ds_image supervl)}"
PORT="${NEMOTRON_35_SUPER_VL_PORT:-$(ds_pick_port "supervl-precision-")}"
CONTAINER="${NEMOTRON_35_SUPER_VL_CONTAINER:-supervl-precision-${PORT}}"
TP="${NEMOTRON_35_SUPER_VL_TP:-}"
GPUS="${NEMOTRON_35_SUPER_VL_GPUS:-all}"; GPUS="${GPUS//\"/}"
[ "$GPUS" = all ] || GPUS="\"$GPUS\""
GPU_MEM_UTIL="${NEMOTRON_35_SUPER_VL_GPU_MEM_UTIL:-0.9}"
MAX_MODEL_LEN="${NEMOTRON_35_SUPER_VL_MAXLEN:-}"
MAX_NUM_SEQS="${NEMOTRON_35_SUPER_VL_MAX_NUM_SEQS:-}"
COMPILE_THREADS="${NEMOTRON_35_SUPER_VL_COMPILE_THREADS:-8}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; CONTAINER="${NEMOTRON_35_SUPER_VL_CONTAINER:-supervl-precision-${PORT}}"; shift 2 ;;
    --tp) TP="$2"; shift 2 ;;
    --gpu-mem-util) GPU_MEM_UTIL="$2"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="$2"; shift 2 ;;
    --max-num-seqs) MAX_NUM_SEQS="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--port PORT] [--tp N] [--gpu-mem-util F] [--max-model-len N] [--max-num-seqs N]"; ds_usage_common; exit 0 ;;
    *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "Unknown option: $1" >&2; exit 3; fi ;;
  esac
done

[[ -n "${TP}" ]] || TP="$(ds_snap_tp)"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-200000}"
if [[ "${TP}" -ge 2 ]]; then : "${MAX_NUM_SEQS:=64}"; else : "${MAX_NUM_SEQS:=8}"; fi

ULIMITS=(--ulimit memlock=-1 --ulimit stack=67108864)
[[ "${NEMOTRON_35_SUPER_VL_ROOTLESS:-0}" == "1" ]] && ULIMITS=(--ulimit stack=67108864)
AR_FLAGS=(); [[ "${NEMOTRON_35_SUPER_VL_DISABLE_CUSTOM_AR:-0}" == "1" ]] && AR_FLAGS=(--disable-custom-all-reduce)
SPEC=()
if [[ "${NEMOTRON_35_SUPER_VL_DFLASH:-0}" == "1" ]]; then
  SPEC=(--speculative-config.method dflash --speculative-config.model "${DRAFT_MODEL}" --speculative-config.num_speculative_tokens 7)
fi

ds_env_args
ds_rm "${CONTAINER}"
ds_pull "${IMAGE}"

ds_docker run -d --restart unless-stopped \
  --gpus "${GPUS}" \
  --ipc=host \
  --shm-size=8g \
  "${ULIMITS[@]}" \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -e TORCHINDUCTOR_COMPILE_THREADS="${COMPILE_THREADS}" -e MAX_JOBS="${COMPILE_THREADS}" \
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_HOME:-$HOME/.cache/huggingface}:/root/.cache/huggingface" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name nvidia/nemotron-3.5-super-vl nemotron-3.5-super-vl auto \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --tensor-parallel-size "${TP}" \
    --enable-expert-parallel \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --max-num-batched-tokens 8192 \
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
    ${SPEC[@]+"${SPEC[@]}"} \
    ${AR_FLAGS[@]+"${AR_FLAGS[@]}"}

echo "Nemotron 3.5 Super VL launched on port ${PORT} (tp=${TP}, ${MAX_MODEL_LEN} ctx, ${MAX_NUM_SEQS} seqs)"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/precision/vllm/health-nemotron-3.5-super-vl-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "nvidia/nemotron-3.5-super-vl" "${CONTAINER}"
