#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Qwen3.8-Flash-Next NVFP4  --  Dell Precision (x86) M-tier alternative recipe
#
# Hardware: Dell Pro Precision 9 T4 (x86_64, 2x RTX PRO 6000 Blackwell, 192 GB)
#           intended target; TP auto-detects the visible GPU count (TP=2 on a
#           T4). The serving path is verified live on a single 252 GB GB300
#           GPU from the same nightly image line (see Validation). Fits on a
#           T2 (1x RTX PRO 6000) with a reduced context/concurrency budget.
# Model   : nvidia/Qwen3.8-Flash-Next-NVFP4  (NVIDIA NVFP4 quantization)
# Role    : M-tier ALTERNATIVE model (default stays the Nemotron pick).
#
# Sizing notes:
#   Qwen4-architecture preview (qwen4_exp): 125B-total MoE, ~6B active per
#   token, native 262K context. The NVFP4 experts are ~68 GiB and stay
#   GPU-resident; the 51B-parameter n-gram ("engram") embedding table (~102 GiB
#   BF16) is offloaded to HOST RAM via --engram-config '{"cpu_offload":true}'
#   — plan for >= 128 GB system RAM. On a T4 with TP=2 the experts split to
#   ~34 GiB/GPU, leaving ~50 GiB/GPU for the FP8-friendly KV budget.
#
#   - Image: vllm/vllm-openai:nightly (multi-arch; the verified serving path
#     ran nightly-aarch64 on GB300 with the identical flag set below).
#   - MTP speculative decoding baked in:
#     --speculative-config '{"method":"mtp","num_speculative_tokens":3}'
#   - --mamba-ssm-cache-dtype bfloat16 (hybrid SSM layers), prefix caching on,
#     --no-enable-flashinfer-autotune (part of the verified flag set).
#   - Tool calling via --tool-call-parser qwen3_xml, reasoning via
#     --reasoning-parser qwen3. Reasoning model — clients keep
#     max_tokens >= 512 (smaller budgets are eaten by the thinking trace).
#   - Restarts with --restart unless-stopped (boot-resume with the model).
#   - Set FLASHNEXT_DIR=/path/to/checkpoint to serve from a pre-copied
#     checkpoint (mounted at /model; no HuggingFace pull — air-gap friendly).
#
# Validation (lab, spot checks):
#   /v1/models, chat completions, and OpenAI tool calling (calculator round
#   trip) all pass against the live endpoint; ~310 out tok/s single-stream on
#   a warm instance (512-token reasoning generation, GB300, MTP x3).
#   T4-specific capacity numbers are pending a measured sweep.
#
# Usage   : ./docker-qwen3.8-flash-next-nvfp4.sh [--port PORT] [--tp N]
#                                                [--gpu-mem-util F]
#                                                [--max-model-len N]
#                                                [--max-num-seqs N]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL="nvidia/Qwen3.8-Flash-Next-NVFP4"
MODEL_DIR="${FLASHNEXT_DIR:-}"
IMAGE="${FLASHNEXT_IMAGE:-$(ds_image flashnext)}"
CONTAINER="${FLASHNEXT_CONTAINER:-flashnext-m-precision}"
PORT="${FLASHNEXT_PORT:-$(ds_pick_port "${FLASHNEXT_CONTAINER:-flashnext-m-precision}")}"
TP="${FLASHNEXT_TP:-}"
GPU_MEM_UTIL="${FLASHNEXT_GPU_MEM_UTIL:-0.9}"
MAX_MODEL_LEN="${FLASHNEXT_MAX_MODEL_LEN:-262144}"
MAX_NUM_SEQS="${FLASHNEXT_MAX_NUM_SEQS:-512}"
# GPU selection: "all" (default) or a docker device list, e.g.
# FLASHNEXT_GPUS='device=0,1' on multi-GPU hosts — when using a subset, set
# FLASHNEXT_TP to the subset count (TP otherwise defaults to the number of
# GPUs the HOST reports).
GPUS="${FLASHNEXT_GPUS:-all}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; shift 2 ;;
    --tp) TP="$2"; shift 2 ;;
    --gpu-mem-util) GPU_MEM_UTIL="$2"; shift 2 ;;
    --max-model-len) MAX_MODEL_LEN="$2"; shift 2 ;;
    --max-num-seqs) MAX_NUM_SEQS="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--port PORT] [--tp N] [--gpu-mem-util F] [--max-model-len N] [--max-num-seqs N]"; ds_usage_common; exit 0 ;;
    *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "Unknown option: $1" >&2; exit 3; fi ;;
  esac
done

[[ -n "${TP}" ]] || TP="$(ds_snap_tp)"   # power of two <= GPU count (3/5-GPU hosts are invalid TPs)

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
if [[ "${FLASHNEXT_ROOTLESS:-0}" == "1" ]]; then
  ULIMITS=(--ulimit stack=67108864)   # rootless docker: memlock=-1 not permitted
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
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_HOME:-$HOME/.cache/huggingface}:/root/.cache/huggingface" \
  "${MODEL_MOUNT[@]}" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name qwen3.8-flash-next qwen3.8-flash-next-nvfp4 auto \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --tensor-parallel-size "${TP}" \
    --mamba-ssm-cache-dtype bfloat16 \
    --no-enable-flashinfer-autotune \
    --enable-prefix-caching \
    --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
    --engram-config '{"cpu_offload":true}' \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    --reasoning-parser qwen3 \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}"

echo "Qwen3.8-Flash-Next NVFP4 launched on port ${PORT} (tp=${TP}, ${MAX_MODEL_LEN} ctx, ${MAX_NUM_SEQS} seqs, MTP x3, engram CPU-offload)"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/precision/vllm/health-qwen3.8-flash-next-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "qwen3.8-flash-next" "${CONTAINER}"
