#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Health assessment for a running serving recipe -- field-debug tool.
# Read-only (except one tiny completion unless --no-smoke). Exit: 0 no FAIL,
# 1 at least one FAIL. Per-recipe wrappers: recipes/<platform>/vllm/health-*.sh
#
# Usage (generic):
#   recipes/lib/health.sh --container NAME --port PORT --served MODEL
#        [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
# Checks: host (docker, nvidia runtime, GPU, memory, disk) -> container
# (state, restarts, OOM, restart policy) -> endpoint (/health, /v1/models,
# smoke completion, optional tool-call) -> metrics (load, KV cache, tok/s)
# -> log signatures with fixes -> monitoring stack.
# ---------------------------------------------------------------------------
_DSH_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H_RES=()          # "STATUS|name|detail|hint"
H_FAIL=0; H_WARN=0

h_add() {  # status name detail [hint]
  H_RES+=("$1|$2|$3|${4:-}")
  [[ "$1" == FAIL ]] && H_FAIL=$((H_FAIL + 1))
  [[ "$1" == WARN ]] && H_WARN=$((H_WARN + 1))
  return 0
}

h_host() {
  command -v docker >/dev/null || { h_add FAIL docker "docker not installed" "install Docker CE + NVIDIA Container Toolkit"; return; }
  docker info >/dev/null 2>&1 || { h_add FAIL docker-daemon "cannot reach docker daemon" "systemctl status docker; add user to docker group"; return; }
  h_add PASS docker "$(docker --version)"
  if docker info --format '{{.Runtimes}}' 2>/dev/null | grep -qw nvidia; then h_add PASS nvidia-runtime "registered"
  else h_add WARN nvidia-runtime "not registered (ok only if default-runtime hook works)" "scripts/landscape/fix-docker-nvidia-runtime.sh"; fi
  if command -v nvidia-smi >/dev/null; then
    h_add PASS gpus "$(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd';' | cut -c1-160)"
    local mem; mem="$(nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader 2>/dev/null | paste -sd";")"
    if grep -qi "N/A" <<<"${mem}"; then h_add SKIP gpu-memory "unified-memory device reports N/A (GB10 behaviour); see host memory below"
    else h_add PASS gpu-memory "${mem}"; fi
  else h_add FAIL nvidia-smi "not found" "install NVIDIA driver"; fi
  local avail; avail="$(awk '/MemAvailable/{printf "%d",$2/1048576}' /proc/meminfo)"
  if (( avail < 8 )); then h_add WARN host-mem-available "${avail} GiB available" "on GB10 GPU and CPU share this pool: stop other memory users or lower --gpu-mem-util"
  else h_add PASS host-mem-available "${avail} GiB available"; fi
  local hf="${HF_HOME:-$HOME/.cache/huggingface}" free
  free="$(df -BG --output=avail "${hf}" 2>/dev/null | tail -1 | tr -dc 0-9)"
  [[ -z "${free}" ]] && free="$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9)"
  if (( free < 25 )); then h_add WARN disk-free "${free} GiB free near ${hf}" "model weights + images need 25-250 GiB depending on recipe"
  else h_add PASS disk-free "${free} GiB free near ${hf}"; fi
}

h_container() {
  local c="$1" st
  if ! docker inspect "${c}" >/dev/null 2>&1; then
    h_add FAIL container "${c} does not exist" "run the recipe (it replaces/creates ${c}); names are in recipes/README.md"; return 1
  fi
  st="$(docker inspect -f '{{.State.Status}}|{{.State.ExitCode}}|{{.RestartCount}}|{{.State.OOMKilled}}|{{.HostConfig.RestartPolicy.Name}}|{{.State.StartedAt}}|{{.Config.Image}}' "${c}")"
  IFS='|' read -r s code rc oom pol started img <<<"${st}"
  [[ "${s}" == running ]] && h_add PASS container-state "running since ${started} (${img})" || h_add FAIL container-state "${s} exit=${code}" "docker logs --tail 100 ${c}"
  [[ "${oom}" == true ]] && h_add FAIL container-oom "OOMKilled by kernel" "lower --gpu-mem-util / --max-num-seqs; free host memory"
  (( rc >= 3 )) && h_add FAIL restarts "RestartCount=${rc}: crash loop" "see log signatures below" || h_add PASS restarts "RestartCount=${rc}"
  [[ "${pol}" == unless-stopped ]] && h_add PASS restart-policy "unless-stopped" || h_add WARN restart-policy "${pol:-none}" "docker update --restart=unless-stopped ${c}"
  [[ "${s}" == running ]]
}

_h_chat() {  # port served max_tokens -> prints raw json
  curl -s -m 120 "${H_AUTH[@]}" "http://${H_PROBE:-127.0.0.1}:$1/v1/chat/completions" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$2\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with: OK\"}],\"max_tokens\":$3,\"temperature\":0}"
}

h_endpoint() {
  local port="$1" served="$2" code models resp t0 t1
  code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://${H_PROBE:-127.0.0.1}:${port}/health" 2>/dev/null)"
  if [[ "${code}" != 200 ]]; then
    h_add FAIL endpoint-health "GET /health -> ${code:-none}" "still loading weights (check docker logs) or port mismatch (ports count up from 8000; see recipes/README.md port map)"; return 1
  fi
  h_add PASS endpoint-health "GET /health -> 200"
  models="$(curl -s -m 10 "${H_AUTH[@]}" "http://${H_PROBE:-127.0.0.1}:${port}/v1/models")"
  if _ds_models_has "${served}" "${models}"; then
    h_add PASS served-model "${served} listed; max_model_len=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["data"][0].get("max_model_len"))' "${models}")"
  else
    h_add FAIL served-model "${served} not in /v1/models: $(python3 -c 'import json,sys;print([m["id"] for m in json.loads(sys.argv[1])["data"]])' "${models}" 2>/dev/null)" "client model name must match a --served-model-name alias"
  fi
  [[ "${H_NO_SMOKE}" == 1 ]] && { h_add SKIP smoke "--no-smoke"; return 0; }
  t0=$(date +%s.%N); resp="$(_h_chat "${port}" "${served}" 128)"; t1=$(date +%s.%N)
  if _ds_msg_ok "${resp}"; then
    h_add PASS smoke "completion ok in $(python3 -c "print(round(${t1}-${t0},2))")s, finish_reason=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["choices"][0]["finish_reason"])' "${resp}")"
  else
    h_add FAIL smoke "no content/reasoning returned: $(cut -c1-160 <<<"${resp}")" "reasoning models need max_tokens >= 512 for real use; if error, check parsers/model name"
  fi
  if python3 -c 'import json,sys;m=json.loads(sys.argv[1])["choices"][0];sys.exit(0 if (not m["message"].get("content") and m["finish_reason"]=="length") else 1)' "${resp:-{\}}" 2>/dev/null; then
    h_add WARN smoke-budget "128 tokens all spent on reasoning (empty content)" "expected for reasoning models; clients must use max_tokens >= 512"
  fi
}

h_toolcall() {
  local port="$1" served="$2" resp
  resp="$(curl -s -m 180 "${H_AUTH[@]}" "http://${H_PROBE:-127.0.0.1}:${port}/v1/chat/completions" -H 'Content-Type: application/json' -d "{\"model\":\"${served}\",\"messages\":[{\"role\":\"user\",\"content\":\"Use the calculator tool to compute 17*23.\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"calculator\",\"description\":\"evaluate arithmetic\",\"parameters\":{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"}},\"required\":[\"expression\"]}}}],\"tool_choice\":\"auto\",\"max_tokens\":1024,\"temperature\":0}")"
  if python3 -c 'import json,sys;sys.exit(0 if json.loads(sys.argv[1])["choices"][0]["message"].get("tool_calls") else 1)' "${resp:-{\}}" 2>/dev/null; then
    h_add PASS tool-call "structured tool_calls returned (parser flags OK)"
  else h_add FAIL tool-call "no structured tool_calls" "model served without matching --tool-call-parser/--reasoning-parser, or max_tokens too small"; fi
}

h_metrics() {
  local port="$1" m1 m2 g1 g2 run wait kv
  m1="$(curl -s -m 5 "http://${H_PROBE:-127.0.0.1}:${port}/metrics")" || true
  [[ -z "${m1}" ]] && { h_add WARN metrics "no /metrics response" "tokenomics dashboard needs it"; return; }
  sleep 5; m2="$(curl -s -m 5 "http://${H_PROBE:-127.0.0.1}:${port}/metrics")"
  _sum() { awk -v k="$1" '$0 ~ "^"k"[{ ]" {s+=$NF} END{printf "%.0f",s}' <<<"$2"; }
  g1="$(_sum 'vllm:generation_tokens_total' "${m1}")"; g2="$(_sum 'vllm:generation_tokens_total' "${m2}")"
  run="$(_sum 'vllm:num_requests_running' "${m2}")"; wait="$(_sum 'vllm:num_requests_waiting' "${m2}")"
  kv="$(awk '/^vllm:kv_cache_usage_perc[{ ]/{print $NF; exit}' <<<"${m2}")"
  h_add PASS load "running=${run} waiting=${wait} output_tok/s(5s)=$(python3 -c "print(round((${g2}-${g1})/5,1))")"
  (( wait > 0 )) && h_add WARN queue "${wait} requests waiting" "scale up / reduce concurrency (--max-num-seqs)"
  [[ -n "${kv}" ]] && python3 -c "import sys;sys.exit(0 if float('${kv}')>0.9 else 1)" && h_add WARN kv-cache "usage ${kv}" "shorten context or reduce concurrency"
  return 0
}

h_logs() {
  local c="$1" logs; logs="$(docker logs --tail 600 "${c}" 2>&1 || true)"
  local found=0 sig fix
  while IFS='|' read -r sig fix; do
    if grep -qiE "${sig}" <<<"${logs}"; then h_add WARN "log:${sig%%|*}" "signature seen in last 600 log lines" "${fix}"; found=1; fi
  done <<'SIGS'
less than desired GPU memory utilization|another process holds GPU/unified memory: stop it or lower --gpu-mem-util
custom_all_reduce\.cuh|PCIe-only GPUs: set NEMOTRON_LIGHTNING_DISABLE_CUSTOM_AR=1 for TP>1 or use TP=1 replicas
vocab.*mismatch|image too old for checkpoint: use vllm/vllm-openai:nightly
CUDA error: out of memory|lower --max-model-len / --max-num-seqs / --gpu-mem-util
unknown or invalid runtime|register nvidia runtime: scripts/landscape/fix-docker-nvidia-runtime.sh
No space left|free disk (HF cache / docker root)
Traceback \(most recent call last\)|python exception in server log: docker logs ${c}
SIGS
  (( found == 0 )) && h_add PASS log-signatures "no known failure signatures in last 600 lines"
  return 0
}

h_monitoring() {
  local c="$1" pp
  if [[ "$(docker inspect -f '{{.State.Running}}' deskside-prometheus 2>/dev/null)" == true ]]; then
    pp="$(docker inspect -f '{{index .Config.Labels "deskside.port"}}' deskside-prometheus)"
    local hp; hp="$(curl -s -m 5 "http://127.0.0.1:${pp}/api/v1/targets" | python3 -c "
import json,sys
c=sys.argv[1]
try: t=[x for x in json.load(sys.stdin)['data']['activeTargets'] if x['labels'].get('container')==c]
except Exception: t=[]
print(t[0]['health'] if t else 'untracked')" "${c}")"
    case "${hp}" in up) h_add PASS monitoring "prometheus :${pp} scraping ${c} (up)";;
      untracked) h_add WARN monitoring "prometheus up but ${c} not a target" "recipes/lib/monitoring.sh up ${c} <port>";;
      *) h_add WARN monitoring "target ${c} is ${hp}" "check /metrics reachable from host";; esac
  else h_add WARN monitoring "deskside-prometheus not running (tokenomics dashboard off)" "re-run recipe without --no-monitoring or: recipes/lib/monitoring.sh up <container> <port>"; fi
}

h_report() {
  local r st name detail hint
  if [[ "${H_JSON}" == 1 ]]; then
    printf '%s\n' "${H_RES[@]}" | python3 -c '
import json,sys
rows=[l.rstrip("\n").split("|",3) for l in sys.stdin]
print(json.dumps({"fail":int(sys.argv[1]),"warn":int(sys.argv[2]),"checks":[dict(status=a,name=b,detail=c,hint=d) for a,b,c,d in rows]},indent=1))' "${H_FAIL}" "${H_WARN}"
  else
    for r in "${H_RES[@]}"; do
      IFS='|' read -r st name detail hint <<<"${r}"
      printf '%-5s %-18s %s\n' "${st}" "${name}" "${detail}"
      [[ -n "${hint}" && "${st}" != PASS ]] && printf '      fix: %s\n' "${hint}"
    done
    echo "---- ${H_FAIL} FAIL, ${H_WARN} WARN ----"
  fi
}

h_bundle() {
  local c="$1" dir="${2:-/tmp}" ts out w; ts="$(date +%Y%m%d-%H%M%S)"
  w="$(mktemp -d)"; out="${dir}/deskside-debug-${c}-${ts}.tgz"
  docker inspect "${c}" 2>&1 | sed -E 's/((HUGGING_FACE_HUB_TOKEN|HF_TOKEN)=)[^"]*/\1<redacted>/g' > "${w}/inspect.json"
  docker logs --tail 2000 "${c}" > "${w}/container.log" 2>&1
  { docker info; docker --version; } > "${w}/docker.txt" 2>&1
  { nvidia-smi; nvidia-smi -L; } > "${w}/nvidia-smi.txt" 2>&1
  { uname -a; cat /etc/os-release; free -m; df -h; ss -tlnp 2>/dev/null; } > "${w}/host.txt" 2>&1
  curl -s -m 5 "http://${H_PROBE:-127.0.0.1}:${H_PORT}/metrics" > "${w}/metrics.txt" 2>&1
  h_report > "${w}/health-report.txt" 2>&1
  tar -C "${w}" -czf "${out}" . && rm -rf "${w}"
  echo "debug bundle: ${out}  (tokens redacted; review before sharing)"
}

# ds_health_main [args]  -- wrappers set H_CONTAINER/H_PORT/H_SERVED defaults, may define recipe_checks()
ds_health_main() {
  H_NO_SMOKE=0; H_JSON=0; local tool=0 bundle=0 bdir=/tmp
  while [[ $# -gt 0 ]]; do case "$1" in
    --container) H_CONTAINER="$2"; shift 2;; --port) H_PORT="$2"; shift 2;;
    --served) H_SERVED="$2"; shift 2;; --tool-test) tool=1; shift;;
    --no-smoke) H_NO_SMOKE=1; shift;; --json) H_JSON=1; shift;;
    --bundle) bundle=1; [[ "${2:-}" && "${2:0:2}" != -- ]] && { bdir="$2"; shift; }; shift;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; return 0;;
    *) echo "unknown option $1" >&2; return 3;; esac; done
  # Resolve defaults from what is actually running (ports count up from 8000 and instances differ)
  if [[ -z "${H_CONTAINER:-}" && -n "${H_CONTAINER_PREFIX:-}" ]]; then
    H_CONTAINER="$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep "^${H_CONTAINER_PREFIX}" | head -1)"
    H_CONTAINER="${H_CONTAINER:-${H_CONTAINER_PREFIX}${DESKSIDE_BASE_PORT:-8000}}"
  fi
  if [[ -z "${H_PORT:-}" && -n "${H_CONTAINER:-}" ]]; then
    H_PORT="$(docker port "${H_CONTAINER}" 8000/tcp 2>/dev/null | head -1 | awk -F: '{print $NF}')"
    H_PORT="${H_PORT:-${DESKSIDE_BASE_PORT:-8000}}"
  fi
  : "${H_CONTAINER:?--container required}" "${H_PORT:?--port required}" "${H_SERVED:?--served required}"
  H_PROBE="${DESKSIDE_PROBE_HOST:-127.0.0.1}"; H_AUTH=(); [[ -n "${DESKSIDE_API_KEY:-}" ]] && H_AUTH=(-H "Authorization: Bearer ${DESKSIDE_API_KEY}")
  h_host
  if h_container "${H_CONTAINER}"; then
    h_endpoint "${H_PORT}" "${H_SERVED}" && { (( tool )) && h_toolcall "${H_PORT}" "${H_SERVED}"; h_metrics "${H_PORT}"; }
  fi
  declare -F recipe_checks >/dev/null && recipe_checks
  docker inspect "${H_CONTAINER}" >/dev/null 2>&1 && h_logs "${H_CONTAINER}"
  h_monitoring "${H_CONTAINER}"
  h_report
  (( bundle )) && h_bundle "${H_CONTAINER}" "${bdir}"
  return $(( H_FAIL > 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  source "${_DSH_LIB}/common.sh"
  ds_health_main "$@"
  exit $?
fi
