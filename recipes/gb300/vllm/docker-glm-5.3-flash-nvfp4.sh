#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# GLM-5.3-Flash NVFP4  --  GB300 UUID-pin recipe (L-tier ALTERNATIVE model)
#
# Hardware: Dell Pro Precision / DGX Station GB300 (aarch64, 252 GB HBM3e).
#           The GB300 GPU is UUID-pinned (auto-detected via nvidia-smi;
#           override with GLM53_GPU_UUID=GPU-…).
# Model   : RedHatAI/GLM-5.3-Flash-NVFP4  (NVFP4 quant of zai-org/GLM-5.3-Flash;
#           ~181 GiB weights. The equivalent LibertAIDAI/GLM-5.3-Flash-NVFP4
#           re-quant works with the same flags — override via GLM53_MODEL.)
# Role    : L-tier ALTERNATIVE model (default stays the Nemotron pick).
#
# Sizing notes:
#   GLM-5.3-Flash is a 320B-total / 18B-active MoE (glm5_next arch, NoPE-MLA
#   sparse attention, multimodal). ~181 GiB of NVFP4 weights leave roughly
#   45 GB of a 252 GB GB300 (util 0.9) for the FP8 KV cache — no CPU expert
#   offloading is required. GB300's sm_100-class path uses the stock Blackwell
#   FP8-KV flags below; sm_121 (GB10)-specific sparse-attention patches from
#   two-GB10 reference recipes do NOT apply here.
#
#   - Image: vllm/vllm-openai:glm53-flash-arm64-cu130 (day-0 GLM-5.3 build;
#     GLM-5.3 support landed here first — plain older tags reject glm5_next).
#   - Tools via --tool-call-parser glm47, reasoning via --reasoning-parser
#     glm45. Reasoning model — clients keep max_tokens >= 512.
#   - Host port: first free port counting up from 8000 (co-hosts with a Lightning
#     instance on shared GB300 app hosts); override with --port or DESKSIDE_BASE_PORT.
#   - Restarts with --restart unless-stopped (boot-resume with the model).
#
# Validation (lab, spot checks, same image + flag set):
#   /v1/models, chat completions, and OpenAI tool calling (calculator round
#   trip) all pass against the live endpoint; ~111 out tok/s single-stream on
#   a warm instance (512-token reasoning generation, 262K ctx).
#
# Usage   : ./docker-glm-5.3-flash-nvfp4.sh [--port PORT]
#                                           [--gpu-mem-util F]
#                                           [--max-model-len N]
#                                           [--max-num-seqs N]
# ---------------------------------------------------------------------------
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

MODEL="${GLM53_MODEL:-RedHatAI/GLM-5.3-Flash-NVFP4}"
IMAGE="${GLM53_IMAGE:-$(ds_image glm53)}"
PORT="${GLM53_PORT:-$(ds_pick_port "${GLM53_CONTAINER:-glm53-flash-gb300}")}"
CONTAINER="${GLM53_CONTAINER:-glm53-flash-gb300}"
GPU_MEM_UTIL="${GLM53_GPU_MEM_UTIL:-0.9}"
MAX_MODEL_LEN="${GLM53_MAX_MODEL_LEN:-262144}"
MAX_NUM_SEQS="${GLM53_MAX_NUM_SEQS:-512}"
HF_CACHE="${GLM53_HF_CACHE:-${HF_HOME:-$HOME/.cache/huggingface}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; shift 2 ;;
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

GPU_UUID="${GLM53_GPU_UUID:-}"
if [[ -z "${GPU_UUID}" ]]; then
  GPU_UUID=$(nvidia-smi --query-gpu=uuid,name --format=csv,noheader \
    | awk -F', ' '/GB300/{print $1; exit}')
fi
if [[ -z "${GPU_UUID}" ]]; then
  echo "ERROR: no GB300 UUID found. Set GLM53_GPU_UUID=GPU-…" >&2
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
  "${DS_ENV_ARGS[@]}" \
  -v "${HF_CACHE}:/root/.cache/huggingface" \
  -p "${DS_BIND_ADDR}:${PORT}:8000" \
  --name "${CONTAINER}" \
  --entrypoint vllm \
  "${IMAGE}" \
  serve "${MODEL}" \
    --served-model-name glm-5.3-flash glm-5.3-flash-nvfp4 auto \
    --host 0.0.0.0 --port 8000 \
    --trust-remote-code \
    --kv-cache-dtype fp8_e4m3 \
    --tensor-parallel-size 1 \
    --moe-backend marlin \
    --enable-auto-tool-choice \
    --tool-call-parser glm47 \
    --reasoning-parser glm45 \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-seqs "${MAX_NUM_SEQS}"

echo "GLM-5.3-Flash NVFP4 (GB300 UUID-pin ${GPU_UUID}) launched on port ${PORT}"
echo "  logs: docker logs -f ${CONTAINER}   health: recipes/gb300/vllm/health-glm-5.3-flash-nvfp4.sh"
ds_finish "${CONTAINER}" "${PORT}" "glm-5.3-flash" "${CONTAINER}"
