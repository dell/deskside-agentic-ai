#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NVIDIA Nemotron 3.5 Lightning 30B A3B (NVFP4)  --  Dell Precision (x86) recipe
#
# Hardware: Dell Pro Precision 9 T2/T4 (x86_64), 1-5x RTX PRO 6000 Blackwell
# Model   : nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4  (NVFP4, ~21 GB weights)
# Role    : x86 Precision build of the Coding Model default (S/M tiers).
#
#   - Image: vllm/vllm-openai:nightly  (required; older tags fail Lightning
#     weight load with vocab/embed size mismatch).
#   - MoE backend: marlin (--moe-backend marlin) + Marlin NVFP4 GEMM
#     (VLLM_NVFP4_GEMM_BACKEND=marlin) — same public-image sm_121 constraint
#     as the GB10 recipe (flashinfer_cutlass is incompatible with this NVFP4
#     quantization scheme). Override with NEMOTRON_LIGHTNING_MOE_BACKEND.
#   - Serving config follows the Blackwell (RTX PRO 6000) reference recipe:
#     0.9 GPU memory utilization, FP8 KV cache, 200K context, and 512
#     concurrent sequences with cudagraph capture sized to match.
#   - TP auto-detects the visible GPU count (set --tp N or
#     NEMOTRON_LIGHTNING_TP=N to pin). One TP=1 instance per GPU is the T6
#     multi-instance pattern; TP>1 spans GPUs on the same tower.
#   - Restarts with --restart unless-stopped (boot-resume with the pinned model).
#   - Set NEMOTRON_LIGHTNING_ROOTLESS=1 to drop the memlock ulimit (rootless
#     Docker on Precision towers).
#   - To serve from a pre-copied checkpoint instead of pulling from HF, set
#     NEMOTRON_LIGHTNING_DIR=/path/to/checkpoint (mounted at /model; no
#     HuggingFace pull).
#   - VLLM_WSL2_ENABLE_PIN_MEMORY=1 is set for WSL2 hosts (pinned memory for
#     staged-write buffers; ignored on regular Linux kernels >= 4.19.121).
#
# Usage   : ./docker-nemotron-3.5-lightning-nvfp4.sh [--port PORT] [--tp N]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL="nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4"
MODEL_DIR="${NEMOTRON_LIGHTNING_DIR:-}"
IMAGE="${NEMOTRON_LIGHTNING_IMAGE:-$(ds_image lightning)}"
PORT="${NEMOTRON_LIGHTNING_PORT:-$(ds_pick_port "lightning-3.5-precision-")}"
# Port-derived default so multi-instance (DP) deploys on one host don't
# docker-rm each other; pin explicitly with NEMOTRON_LIGHTNING_CONTAINER.
CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-lightning-3.5-precision-${PORT}}"
TP="${NEMOTRON_LIGHTNING_TP:-}"
MOE_BACKEND="${NEMOTRON_LIGHTNING_MOE_BACKEND:-marlin}"
GPU_MEM_UTIL="${NEMOTRON_LIGHTNING_GPU_MEM_UTIL:-0.9}"
# GPU selection: "all" (default) or a docker device list, e.g.
# NEMOTRON_LIGHTNING_GPUS='device=0,1' on multi-GPU hosts — when using a
# subset, set NEMOTRON_LIGHTNING_TP to the subset count (TP otherwise
# snaps to the largest power of two <= the HOST's GPU count).
GPUS="${NEMOTRON_LIGHTNING_GPUS:-all}"
GPUS="${GPUS//\"/}"                    # tolerate pre-quoted input
[ "$GPUS" = all ] || GPUS="\"$GPUS\""  # docker needs inner quotes on device lists
MAX_MODEL_LEN="${NEMOTRON_LIGHTNING_MAX_MODEL_LEN:-200000}"
MAX_NUM_SEQS="${NEMOTRON_LIGHTNING_MAX_NUM_SEQS:-512}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-lightning-3.5-precision-${PORT}}"; shift 2 ;;
    --tp) TP="$2"; shift 2 ;;
    --gpu-mem-util) GPU_MEM_UTIL="$2"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="$2"; shift 2 ;;
    --max-num-seqs) MAX_NUM_SEQS="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--port PORT] [--tp N] [--gpu-mem-util F] [--max-model-len N] [--max-num-seqs N]"; ds_usage_common; exit 0 ;;
    *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "Unknown option: $1" >&2; exit 3; fi ;;
  esac
done

if [[ -z "${TP}" ]]; then
  # Snap to the largest power of two <= host GPU count: attention-head counts
  # are powers of two, so a naive host-count default (3, 5, ...) is always an
  # invalid TP (vLLM rejects non-divisors of the head count). Override with
  # NEMOTRON_LIGHTNING_TP for any other layout.
  N=$(nvidia-smi -L 2>/dev/null | wc -l); N="${N:-1}"
  TP=1; while [ $((TP * 2)) -le "$N" ]; do TP=$((TP * 2)); done
  [[ "${TP}" -ge 1 ]] || TP=1
fi

MODEL_MOUNT=()
if [[ -n "${MODEL_DIR}" && -d "${MODEL_DIR}" ]]; then
  case "${MODEL_DIR}" in
    */models--*/snapshots/*)
      # A Hugging Face cache snapshot is a tree of symlinks into ../blobs;
      # mounting the snapshot alone leaves them dangling in the container.
      # Mount the whole repo dir at its own path and serve the snapshot in it.
      MODEL_MOUNT=("-v" "${MODEL_DIR%/snapshots/*}:${MODEL_DIR%/snapshots/*}")
      MODEL="${MODEL_DIR}" ;;
    *)
      MODEL_MOUNT=("-v" "${MODEL_DIR}:/model")
      MODEL="/model" ;;
  esac
fi

ULIMITS=(--ulimit memlock=-1 --ulimit stack=67108864)
if [[ "${NEMOTRON_LIGHTNING_ROOTLESS:-0}" == "1" ]]; then
  ULIMITS=(--ulimit stack=67108864)   # rootless docker: memlock=-1 not permitted
fi

# PCIe-only GPU pairs (e.g. RTX PRO 6000 on T4/T6-class hosts) have no P2P
# fabric: vLLM's custom all-reduce kernel aborts there with
# "custom_all_reduce.cuh invalid argument". Set
# NEMOTRON_LIGHTNING_DISABLE_CUSTOM_AR=1 for TP>1 on such boxes; NVLink
# systems (GB200/GB300) keep the faster default.
AR_FLAGS=()
if [[ "${NEMOTRON_LIGHTNING_DISABLE_CUSTOM_AR:-0}" == "1" ]]; then
  AR_FLAGS=(--disable-custom-all-reduce)
fi

ds_pull "${IMAGE}"
ds_env_args
ds_rm "${CONTAINER}"

ds_docker run -d --restart unless-stopped \
  --gpus "${GPUS}" \
  --ipc=host \
  --shm-size=8g \
  "${ULIMITS[@]}" \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -e VLLM_NVFP4_GEMM_BACKEND=marlin \
  -e VLLM_WSL2_ENABLE_PIN_MEMORY=1 \
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_HOME:-$HOME/.cache/huggingface}:/root/.cache/huggingface" \
  "${MODEL_MOUNT[@]}" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name nvidia/nemotron-3.5-lightning nemotron-lightning lightning auto \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --tensor-parallel-size "${TP}" \
    --moe-backend "${MOE_BACKEND}" \
    --kv-cache-dtype fp8 \
    --enable-expert-parallel \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser nemotron_v3 \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --max-cudagraph-capture-size "${MAX_NUM_SEQS}" \
    "${AR_FLAGS[@]}"

echo "Nemotron 3.5 Lightning launched on port ${PORT} (tp=${TP}, ${MAX_MODEL_LEN} ctx, ${MAX_NUM_SEQS} seqs)"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/precision/vllm/health-nemotron-3.5-lightning-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "nvidia/nemotron-3.5-lightning" "${CONTAINER}"
