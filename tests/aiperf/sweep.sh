#!/usr/bin/env bash
# Run an aiperf concurrency ladder against a serving recipe's endpoint and save
# date/commit-coded, fully traceable results.
#
#   tests/aiperf/sweep.sh --url http://localhost:8000 --model nvidia/nemotron-3.5-lightning \
#       --tokenizer nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4 \
#       --shape agent_60k_1k --ladder agent --container lightning-3.5-gb10 [--platform gb10] [--dry-run]
#
# Output: tests/data/<YYYYMMDD>_<gitsha>/<platform>_<model-slug>_<shape>/
#           MANIFEST.json  (git sha, dirty, host, GPUs, image id, container args, ladder, aiperf version)
#           commands.txt   (exact aiperf command per level)   levelC<n>/ (raw aiperf export)
#           ladder.json    (per-level aggregate / per-session / TTFT / ITL via summarize.py)
# NOTE: do not run while another benchmark owns the GPU; one driver per model (artifact-dir collisions).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "${HERE}/../.." && pwd)"
URL=""; MODEL=""; TOK=""; SHAPE=agent_60k_1k; LADDER=agent; CONTAINER=""; PLATFORM=""; DRY=0; REQ=""; KEYFILE=""
while [[ $# -gt 0 ]]; do case "$1" in
  --url) URL="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --tokenizer) TOK="$2"; shift 2;;
  --shape) SHAPE="$2"; shift 2;; --ladder) LADDER="$2"; shift 2;; --container) CONTAINER="$2"; shift 2;;
  --platform) PLATFORM="$2"; shift 2;; --api-key-file) KEYFILE="$2"; shift 2;; --requests) REQ="$2"; shift 2;; --dry-run) DRY=1; shift;;
  -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0;; *) echo "unknown $1" >&2; exit 3;; esac; done
: "${URL:?--url}" "${MODEL:?--model}" "${TOK:?--tokenizer}"
read -r ISL OSL RC LADDER_CS < <(python3 - "${HERE}/shapes.yaml" "${SHAPE}" "${LADDER}" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])); s = d["shapes"][sys.argv[2]]
print(s["isl"], s["osl"], s["request_count"], ",".join(map(str, d["ladders"][sys.argv[3]])))
PY
)
[[ -n "${REQ}" ]] && RC="${REQ}"
SHA="${DESKSIDE_GIT_SHA:-$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo nogit)}"
PLATFORM="${PLATFORM:-$(hostname)}"; SLUG="$(tr '/:' '--' <<<"${MODEL}")"
OUT="${ROOT}/tests/data/$(date +%Y%m%d)_${SHA}/${PLATFORM}_${SLUG}_${SHAPE}"
mkdir -p "${OUT}"; : > "${OUT}/commands.txt"
AIPERF="${AIPERF:-aiperf}"
python3 - "${OUT}/MANIFEST.json" <<PY
import json, re, subprocess, sys, time
def sh(c):
    try: return subprocess.run(c, shell=True, capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception as e: return str(e)
def neut(s): return re.sub(r"GPU-[0-9a-fA-F-]{36}", "<GPU-UUID>", s)  # committed records never carry host identity
m = {"date": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "git_sha": "${SHA}", "host": "lab host", "platform": "${PLATFORM}",
     "model": "${MODEL}", "tokenizer": "${TOK}", "url": "${URL}", "shape": "${SHAPE}", "isl": ${ISL}, "osl": ${OSL}, "request_count": ${RC},
     "ladder": [${LADDER_CS}], "aiperf": sh("${AIPERF} --version 2>&1 | head -1"), "gpus": sh("docker exec ${CONTAINER} nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sort | uniq -c | sed 's/^ *//' | paste -sd '; '") or sh("nvidia-smi --query-gpu=name --format=csv,noheader | sort | uniq -c | sed 's/^ *//' | paste -sd '; '"),
     "container": "${CONTAINER}", "image": sh("docker inspect -f '{{.Image}} {{.Config.Image}}' ${CONTAINER} 2>/dev/null"),
     "container_args": neut(sh("docker inspect -f '{{join .Args \" \"}}' ${CONTAINER} 2>/dev/null"))}
json.dump(m, open(sys.argv[1], "w"), indent=1)
PY
IFS=, read -ra CS <<<"${LADDER_CS}"
for C in "${CS[@]}"; do
  N=$RC; [[ "${SHAPE}" != agent_60k_1k ]] && N=$(( RC > 4*C ? RC : 4*C ))
  ARGV=("${AIPERF}" profile -m "${MODEL}" --endpoint-type chat --endpoint /v1/chat/completions --url "${URL}" --streaming
    --synthetic-input-tokens-mean "${ISL}" --synthetic-input-tokens-stddev 0 --output-tokens-mean "${OSL}"
    --extra-inputs "min_tokens:${OSL}" --extra-inputs ignore_eos:true --tokenizer "${TOK}"
    ${KEYFILE:+--api-key "$(<"${KEYFILE}")"} --concurrency "${C}" --request-count "${N}" --artifact-dir "${OUT}/levelC${C}" --profile-export-file "profile_c${C}.json")
  LOGV=("${ARGV[@]}")   # logged copy never carries the live key; the run uses ARGV
  if [[ -n "${KEYFILE}" ]]; then for ((i=1;i<${#LOGV[@]};i++)); do [[ "${LOGV[i-1]}" == "--api-key" ]] && LOGV[i]="<DESKSIDE_API_KEY>"; done; fi
  printf '%q ' "${LOGV[@]}" >> "${OUT}/commands.txt"; echo >> "${OUT}/commands.txt"
  [[ "${DRY}" == 1 ]] && { printf '[dry-run] '; printf '%q ' "${ARGV[@]}"; echo; continue; }
  echo "== C=${C} (${N} requests)"; "${ARGV[@]}"
done
[[ "${DRY}" == 1 ]] && { echo "dry-run: nothing executed; manifest+commands in ${OUT}"; exit 0; }
python3 "${HERE}/summarize.py" "${OUT}"
echo "results: ${OUT}"
