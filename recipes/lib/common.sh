#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Shared helpers for every serving recipe (source this; do not execute).
#
# Contract every recipe now satisfies ("readiness contract"):
#   1. build/launch : pull image, replace any old container, docker run -d
#   2. monitor      : start/refresh the shared tokenomics Prometheus+Grafana
#                     (recipes/lib/monitoring.sh) unless --no-monitoring
#   3. ready        : BLOCK until the endpoint is truly serving, then print one
#                     machine-readable line:  READY {"container":..,"port":..,..}
#   Exit codes: 0 ready | 1 container died / crash-looping | 2 wait timeout
#               3 invalid usage / launch failure
# Common flags (all recipes): --no-wait  --wait-timeout SEC  --no-monitoring  --dry-run
#                             --bind ADDR  --api-key-file FILE
# Env: DESKSIDE_BASE_PORT=8000 (ports count up from here)  DESKSIDE_BIND_ADDR=0.0.0.0
#      DESKSIDE_API_KEY (-> VLLM_API_KEY inside the container)  DESKSIDE_IMAGE_CHANNEL=release|digest|nightly
#      DESKSIDE_WAIT=0|1  DESKSIDE_WAIT_TIMEOUT=1800  DESKSIDE_WAIT_INTERVAL=5
#      DESKSIDE_MONITORING=0|1  DESKSIDE_DRY_RUN=0|1  DESKSIDE_PULL_TIMEOUT=60
# Health/debug for a running recipe: recipes/<platform>/vllm/health-*.sh
# ---------------------------------------------------------------------------
DS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DS_REPO_ROOT="$(cd "${DS_LIB_DIR}/../.." && pwd)"
DS_DRY_RUN="${DESKSIDE_DRY_RUN:-0}"
DS_WAIT="${DESKSIDE_WAIT:-1}"
DS_WAIT_TIMEOUT="${DESKSIDE_WAIT_TIMEOUT:-1800}"
DS_WAIT_INTERVAL="${DESKSIDE_WAIT_INTERVAL:-5}"
DS_MONITORING="${DESKSIDE_MONITORING:-1}"
DS_PULL_TIMEOUT="${DESKSIDE_PULL_TIMEOUT:-60}"
DS_SHIFT=0
DS_BASE_PORT="${DESKSIDE_BASE_PORT:-8000}"
DS_BIND_ADDR="${DESKSIDE_BIND_ADDR:-0.0.0.0}"
DS_API_KEY="${DESKSIDE_API_KEY:-}"
DS_LOCK="${DS_LIB_DIR}/../versions.lock"
DS_PROBE_HOST=127.0.0.1
DS_CURL_AUTH=()
DS_ENV_ARGS=()

# shellcheck source=/dev/null
source "${DS_LIB_DIR}/monitoring.sh"

ds_usage_common() {
  echo "Common: [--no-wait] [--wait-timeout SEC] [--no-monitoring] [--dry-run] [--bind ADDR] [--api-key-file FILE]"
}

# Recipes call this from their arg loop: `if ds_common_flag "$@"; then shift "$DS_SHIFT"; continue; fi`
ds_common_flag() {
  case "${1:-}" in
    --no-wait) DS_WAIT=0; DS_SHIFT=1 ;;
    --wait-timeout) DS_WAIT_TIMEOUT="${2:?--wait-timeout needs SECONDS}"; DS_SHIFT=2 ;;
    --no-monitoring) DS_MONITORING=0; DS_SHIFT=1 ;;
    --dry-run) DS_DRY_RUN=1; DS_SHIFT=1 ;;
    --bind) DS_BIND_ADDR="${2:?--bind needs ADDR}"; DS_SHIFT=2 ;;
    --api-key-file) DS_API_KEY="$(<"${2:?--api-key-file needs FILE}")"; DS_SHIFT=2 ;;
    *) return 1 ;;
  esac
  return 0
}

ds_log() { echo "[deskside] $*" >&2; }

# docker wrapper: prints instead of running under --dry-run
ds_docker() {
  if [[ "${DS_DRY_RUN}" == "1" ]]; then
    { printf '[dry-run] docker'; printf ' %q' "$@"; printf '\n'; } \
      | sed -E 's/((HUGGING_FACE_HUB_TOKEN|HF_TOKEN)=)[^ ]*/\1<redacted>/g'
    return 0
  fi
  docker "$@"
}

ds_pull() {
  local image="$1"
  if [[ "${DS_DRY_RUN}" == "1" ]]; then echo "[dry-run] docker pull ${image}"; return 0; fi
  timeout "${DS_PULL_TIMEOUT}" docker pull "${image}" \
    || ds_log "warn: docker pull failed/timed out (${DS_PULL_TIMEOUT}s); using local image if present"
}

ds_rm() {
  if [[ "${DS_DRY_RUN}" == "1" ]]; then echo "[dry-run] docker rm -f $1"; return 0; fi
  docker rm -f "$1" >/dev/null 2>&1 || true
}

# ds_pick_port OWN  -> first usable port >= DESKSIDE_BASE_PORT (8000), counting up.
# A busy port is reusable when it is published by OWN (exact container name) or OWN<port>
# (prefix style, e.g. vllm_8001), so re-running a recipe replaces its own instance in place.
ds_pick_port() {
  local own="${1:-}" p="${DS_BASE_PORT}" names
  while :; do
    if _dsm_port_free "${p}"; then echo "${p}"; return 0; fi
    names="$(docker ps --filter "publish=${p}" --format '{{.Names}}' 2>/dev/null || true)"
    if [[ -n "${own}" ]] && grep -qxE "${own}|${own}${p}" <<<"${names}"; then echo "${p}"; return 0; fi
    p=$((p + 1))
  done
}

# ds_image ID  -> image reference by policy: release (if validated) -> digest -> nightly
ds_image() {
  local id="$1" arch rel val dg_a dg_x nightly pick why dg
  arch="$(uname -m)"
  IFS='|' read -r _ rel val dg_a dg_x nightly _ < <(grep -E "^${id}\|" "${DS_LOCK}" || true)
  [[ -n "${nightly:-}" ]] || { echo "ds_image: no lock entry for '${id}' in ${DS_LOCK}" >&2; return 1; }
  [[ "${arch}" == aarch64 || "${arch}" == arm64 ]] && dg="${dg_a}" || dg="${dg_x}"
  case "${DESKSIDE_IMAGE_CHANNEL:-auto}" in
    release) pick="${rel}"; why="forced release";;
    digest)  pick="${dg}";  why="forced digest";;
    nightly) pick="${nightly}"; why="forced nightly";;
    *) if [[ "${rel}" != "-" && "${val}" == yes ]]; then pick="${rel}"; why="validated release"
       elif [[ "${dg}" != "-" ]]; then pick="${dg}"; why="digest (no validated release; ${arch})"
       elif [[ "${nightly}" =~ nightly-[0-9a-f]{7,} ]]; then pick="${nightly}"; why="pinned nightly tag: no validated release / ${arch} digest yet"
       else pick="${nightly}"; why="MOVING nightly fallback: no validated release or ${arch} digest recorded -- not reproducible"; fi;;
  esac
  [[ -n "${pick}" && "${pick}" != "-" ]] || { echo "ds_image: channel has no pin for '${id}'" >&2; return 1; }
  echo "[deskside] image ${id}: ${pick} (${why})" >&2
  echo "${pick}"
}

# Environment passed BY NAME (values never appear on the docker command line / in `ps`):
#   HUGGING_FACE_HUB_TOKEN (from HF_TOKEN) and VLLM_API_KEY (from DESKSIDE_API_KEY).
ds_env_args() {
  DS_ENV_ARGS=()
  export HUGGING_FACE_HUB_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
  [[ -n "${HUGGING_FACE_HUB_TOKEN}" ]] && DS_ENV_ARGS+=(-e HUGGING_FACE_HUB_TOKEN)
  if [[ -n "${DS_API_KEY}" ]]; then export VLLM_API_KEY="${DS_API_KEY}"; DS_ENV_ARGS+=(-e VLLM_API_KEY); fi
  # host used by probes / monitoring: loopback unless bound to one specific non-loopback address
  case "${DS_BIND_ADDR}" in 0.0.0.0|127.0.0.1|"") DS_PROBE_HOST=127.0.0.1;; *) DS_PROBE_HOST="${DS_BIND_ADDR}";; esac
  DS_CURL_AUTH=(); [[ -n "${DS_API_KEY}" ]] && DS_CURL_AUTH=(-H "Authorization: Bearer ${DS_API_KEY}")
  return 0
}

# ds_snap_tp [N]  -> largest power of two <= N (default: visible GPU count). Attention-head counts are
# powers of two, so 3/5/6-GPU hosts need TP in {1,2,4}; vLLM rejects non-divisors.
ds_snap_tp() {
  local n="${1:-$(nvidia-smi -L 2>/dev/null | wc -l)}" tp=1
  n="${n:-1}"; while [ $((tp * 2)) -le "${n}" ]; do tp=$((tp * 2)); done
  echo "${tp}"
}

# Pass --runtime=nvidia only when the daemon registers that runtime.
ds_runtime_opt() {
  DS_RUNTIME_OPT=()
  docker info --format '{{.Runtimes}}' 2>/dev/null | grep -qw nvidia && DS_RUNTIME_OPT=(--runtime=nvidia) || true
}

_ds_json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

_ds_models_has() {
  python3 -c 'import json,sys;sys.exit(0 if sys.argv[1] in [m["id"] for m in json.loads(sys.argv[2])["data"]] else 1)' "$1" "$2" 2>/dev/null
}
_ds_msg_ok() {
  python3 -c '
import json,sys
m=json.loads(sys.argv[1])["choices"][0]["message"]
sys.exit(0 if (m.get("content") or m.get("reasoning_content") or m.get("reasoning")) else 1)' "$1" 2>/dev/null
}

# Print last log lines + known-signature hints for a failed container.
ds_diagnose() {
  local c="$1"
  ds_log "---- last 40 log lines of ${c} ----"
  docker logs --tail 40 "${c}" 2>&1 | sed 's/^/    /' >&2 || true
  local logs; logs="$(docker logs --tail 400 "${c}" 2>&1 || true)"
  grep -qi "less than desired GPU memory utilization" <<<"${logs}" && \
    ds_log "HINT: another process holds GPU/unified memory -> stop it or lower --gpu-mem-util"
  grep -qi "custom_all_reduce.cuh" <<<"${logs}" && \
    ds_log "HINT: PCIe-only GPUs -> set NEMOTRON_LIGHTNING_DISABLE_CUSTOM_AR=1 (TP>1) or use TP=1 replicas"
  grep -qiE "vocab|embed.*size mismatch" <<<"${logs}" && \
    ds_log "HINT: image too old for this checkpoint -> use vllm/vllm-openai:nightly (or the recipe's pinned image)"
  grep -qiE "out of memory|CUDA error: out of memory|OOM" <<<"${logs}" && \
    ds_log "HINT: out of memory -> lower --max-model-len/--max-num-seqs/--gpu-mem-util"
  grep -qiE "unknown or invalid runtime name" <<<"${logs}" && \
    ds_log "HINT: NVIDIA runtime not registered -> scripts/landscape/fix-docker-nvidia-runtime.sh"
  grep -qiE "No space left" <<<"${logs}" && ds_log "HINT: disk full (HF cache / docker root)"
  ds_log "More: recipes/<platform>/vllm/health-*.sh --bundle"
}

# ds_wait_ready CONTAINER PORT SERVED_NAME [TIMEOUT]
# Ready == container running AND /health 200 AND /v1/models lists SERVED_NAME
#          AND a tiny chat completion succeeds (generation path exercised).
ds_wait_ready() {
  local c="$1" port="$2" served="$3" timeout="${4:-${DS_WAIT_TIMEOUT}}"
  local start now elapsed last_beat=0 state code restarts oom models resp
  start=$(date +%s)
  ds_log "waiting for ${c} on :${port} (timeout ${timeout}s; first run downloads weights)"
  while :; do
    now=$(date +%s); elapsed=$((now - start))
    state="$(docker inspect -f '{{.State.Status}}|{{.State.ExitCode}}|{{.RestartCount}}|{{.State.OOMKilled}}' "${c}" 2>/dev/null || echo "missing|0|0|false")"
    IFS='|' read -r st code restarts oom <<<"${state}"
    if [[ "${st}" == "missing" || "${st}" == "exited" || "${st}" == "dead" || "${st}" == "restarting" ]]; then
      ds_log "FAILED: container ${c} state=${st} exit=${code} restarts=${restarts} oom=${oom}"
      ds_diagnose "${c}"
      return 1
    fi
    if [[ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://${DS_PROBE_HOST:-127.0.0.1}:${port}${DS_HEALTH_PATH:-/health}" 2>/dev/null)" == "200" ]]; then
      models="$(curl -s -m 10 "${DS_CURL_AUTH[@]}" "http://${DS_PROBE_HOST:-127.0.0.1}:${port}/v1/models" 2>/dev/null || true)"
      if _ds_models_has "${served}" "${models}"; then
        resp="$(curl -s -m 120 "${DS_CURL_AUTH[@]}" "http://${DS_PROBE_HOST:-127.0.0.1}:${port}/v1/chat/completions" -H 'Content-Type: application/json' \
          -d "{\"model\":\"${served}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with: OK\"}],\"max_tokens\":64,\"temperature\":0}" 2>/dev/null || true)"
        if _ds_msg_ok "${resp}"; then
          DS_READY_MODELS="$(python3 -c 'import json,sys;print(json.dumps([m["id"] for m in json.loads(sys.argv[1])["data"]]))' "${models}")"
          DS_READY_SECONDS="${elapsed}"
          DS_READY_MAXLEN="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["data"][0].get("max_model_len") or 0)' "${models}" 2>/dev/null || echo 0)"
          return 0
        fi
      fi
    fi
    if [[ "${restarts}" -ge 3 ]]; then
      ds_log "FAILED: container ${c} crash-looping (restarts=${restarts}, not healthy)"
      ds_diagnose "${c}"
      return 1
    fi
    if (( elapsed - last_beat >= 30 )); then
      last_beat=${elapsed}
      ds_log "  ... ${elapsed}s state=${st} | $(docker logs --tail 1 "${c}" 2>&1 | cut -c1-120)"
    fi
    if (( elapsed >= timeout )); then
      ds_log "TIMEOUT after ${timeout}s waiting for ${c} (container still ${st})"
      ds_diagnose "${c}"
      return 2
    fi
    sleep "${DS_WAIT_INTERVAL}"
  done
}

# ds_client_limits MAX_MODEL_LEN -> "<max_output> <prompt_budget>"
# Rule: agent clients must never request more than the server window.
#   max_output   = min(16384, max_model_len/8)  rounded down to 512   (>= 512 so reasoning models can answer)
#   prompt_budget = max_model_len - max_output - 1024 safety margin (system prompt + tool schemas + history)
ds_client_limits() {
  python3 -c '
import sys
n=int(sys.argv[1]); out=max(512,min(16384,n//8)//512*512)
print(out, max(0,n-out-1024))' "$1"
}

# ds_finish CONTAINER PORT SERVED_NAME LABEL
# Call as the LAST step of a recipe (after `docker run -d`).
ds_finish() {
  local c="$1" port="$2" served="$3" label="${4:-$1}"
  if [[ "${DS_DRY_RUN}" == "1" ]]; then
    echo "[dry-run] would start monitoring (DESKSIDE_MONITORING=${DS_MONITORING}) and wait for ${c} on :${port} (served name ${served})"
    return 0
  fi
  if [[ -z "${DS_API_KEY}" && "${DS_BIND_ADDR}" == "0.0.0.0" ]]; then
    ds_log "WARNING: ${c} is serving on ALL interfaces (0.0.0.0:${port}) with NO API key. Anyone on this network can use the GPU and the endpoint is unauthenticated."
    ds_log "         Restrict with --bind 127.0.0.1 or set DESKSIDE_API_KEY / --api-key-file, and put TLS/identity in your own gateway."
  fi
  if [[ "${DS_MONITORING}" == "1" ]]; then
    DESKSIDE_PROBE_HOST="${DS_PROBE_HOST:-127.0.0.1}" ds_monitoring_up "${c}" "${port}" "${label}" \
      || ds_log "warn: monitoring not started (serving is unaffected); retry: recipes/lib/monitoring.sh up ${c} ${port} ${label}"
  fi
  if [[ "${DS_WAIT}" == "1" ]]; then
    ds_wait_ready "${c}" "${port}" "${served}" "${DS_WAIT_TIMEOUT}" || exit $?
    local lim="" ; if [[ "${DS_READY_MAXLEN:-0}" -gt 0 ]]; then read -r _o _p <<<"$(ds_client_limits "${DS_READY_MAXLEN}")"; lim=",\"max_model_len\":${DS_READY_MAXLEN},\"client_max_output_tokens\":${_o},\"client_prompt_budget_tokens\":${_p}"; fi
    echo "READY {\"ready\":true,\"container\":$(_ds_json_escape "${c}"),\"port\":${port},\"base_url\":\"http://localhost:${port}/v1\",\"bind\":\"${DS_BIND_ADDR}\",\"auth\":\"$([[ -n "${DS_API_KEY}" ]] && echo api-key || echo none)\",\"served_name\":$(_ds_json_escape "${served}"),\"models\":${DS_READY_MODELS},\"seconds_to_ready\":${DS_READY_SECONDS}${lim},\"prometheus\":$(_ds_json_escape "${DS_PROM_URL:-}"),\"grafana\":$(_ds_json_escape "${DS_GRAFANA_URL:-}")}"
  else
    echo "NOT-WAITING (--no-wait): poll with  recipes/lib/health.sh --container ${c} --port ${port} --served ${served}"
  fi
  [[ -n "${DS_GRAFANA_URL:-}" ]] && ds_log "tokenomics dashboard: ${DS_GRAFANA_URL}  (admin password: ${DS_MON_DIR}/grafana-admin-password)"
  return 0
}
