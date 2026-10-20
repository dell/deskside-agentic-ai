#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Qwen3.8-27B-NVFP4 with MTP  --  DGX Spark (GB10) recipe
#
# Hardware: NVIDIA GB10 (128 GB unified memory)
# Image   : vllm/vllm-openai:nightly  (the qwen3_5 architecture and the
#           "mtp" speculative method ship in current vLLM builds)
# Model   : nvidia/Qwen3.8-27B-NVFP4  (ModelOpt NVFP4 of Qwen/Qwen3.8-27B;
#           ships the MTP draft head, kept BF16 by the quantizer)
# Role    : S-tier ALTERNATIVE to the Coding Model default (Nemotron 3.5
#           Lightning). Dense 27B, NVFP4, hybrid linear/full attention.
#
# Sizing notes:
#   ~18 GB quantized weights + BF16 MTP head/norms. The full 262K context window
#   with FP8 KV cache fits on a single GB10 at 0.9 memory utilization.
#
# Tool / reasoning support:
#   Tool calling via --tool-call-parser qwen3_coder.
#   Reasoning (thinking mode) via --reasoning-parser qwen3 — like the default
#   model this is a reasoning model: clients must keep max_tokens >= 512 or
#   the thinking trace eats the whole budget.
#
# MTP (multi-token prediction):
#   Speculative decode via the model's built-in MTP head:
#   --speculative-config '{"method": "mtp", "num_speculative_tokens": 2}'
#   (checkpoint config: mtp_num_hidden_layers = 1). ~62-65 out tok/s
#   single-stream measured on GB10 with the predecessor unsloth/ NVFP4
#   checkpoint; re-sweep pending on this nvidia/ pin.
#
# Local-copy deployment:
#   Set QWEN38_27B_DIR=/path/to/checkpoint to serve a pre-copied checkpoint
#   (mounted at /model; no Hugging Face pull).
#
# GPU selection:
#   QWEN38_27B_GPUS=all (default, whole card) — or a docker device list such
#   as QWEN38_27B_GPUS='device=0,1' to bind the server to specific GPUs on
#   multi-GPU hosts (T4/T6 fleets).
#
# Tunables: QWEN38_27B_GPU_MEM_UTIL (default 0.9 of the 128 GB unified pool -- lower to ~0.7 when
#           other processes share the memory; see health wrapper)
# Usage   : ./docker-qwen3.8-27b-nvfp4.sh [--port PORT]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL_REPO="nvidia/Qwen3.8-27B-NVFP4"
MODEL_DIR="${QWEN38_27B_DIR:-}"
IMAGE="${QWEN38_27B_IMAGE:-$(ds_image qwen27b)}"
CONTAINER="${QWEN38_27B_CONTAINER:-qwen38-27b-gb10}"
PORT="${QWEN38_27B_PORT:-$(ds_pick_port "${QWEN38_27B_CONTAINER:-qwen38-27b-gb10}")}"
SPEC_TOKENS="${QWEN38_27B_SPEC_TOKENS:-2}"
GPUS="${QWEN38_27B_GPUS:-all}"
GPUS="${GPUS//\"/}"                    # tolerate pre-quoted input
[ "$GPUS" = all ] || GPUS="\"$GPUS\""  # docker needs inner quotes on device lists

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; shift 2 ;;
    --spec-tokens) SPEC_TOKENS="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--port PORT] [--spec-tokens N]"; ds_usage_common; exit 0 ;;
    *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "Unknown option: $1" >&2; exit 3; fi ;;
  esac
done

MODEL="${MODEL_DIR:-$MODEL_REPO}"
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

ds_pull "${IMAGE}"
ds_env_args
ds_rm "${CONTAINER}"

# Pass --runtime=nvidia only when the daemon registers that runtime. Hosts
# whose toolkit works through the default-runtime hook alone still get GPUs
# via --gpus; hardcoding the runtime would fail the run there.
ds_runtime_opt

ds_docker run -d --restart unless-stopped \
  ${DS_RUNTIME_OPT[@]+"${DS_RUNTIME_OPT[@]}"} \
  --gpus "${GPUS}" \
  --ipc=host \
  --shm-size=8g \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_HOME:-$HOME/.cache/huggingface}:/root/.cache/huggingface" \
  "${MODEL_MOUNT[@]}" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name qwen3.8-27b qwen3.8 \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --kv-cache-dtype fp8 \
    --max-model-len 262144 \
    --gpu-memory-utilization "${QWEN38_27B_GPU_MEM_UTIL:-0.9}" \
    --enable-prefix-caching \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser qwen3 \
    --speculative-config "{\"method\": \"mtp\", \"num_speculative_tokens\": ${SPEC_TOKENS}}"

echo "Qwen3.8-27B-NVFP4 (MTP spec-decode, ${SPEC_TOKENS} tokens) launched on port ${PORT}"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/gb10/vllm/health-qwen3.8-27b-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "qwen3.8-27b" "${CONTAINER}"
