#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Data-parallel launcher: N replicas of one recipe + a LiteLLM front door.
#   Front door = base port (8000, DESKSIDE_BASE_PORT) so clients never change;
#   replicas count up from base+1 (8001, 8002, ...), pinned to GPUs, TP per replica.
#
#   recipes/lib/launch-replicas.sh --recipe recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh \
#       --env-prefix NEMOTRON_LIGHTNING --served nvidia/nemotron-3.5-lightning \
#       [--replicas 5 | --gpu-groups "0 1 2 3 4"] [--tp 1] [-- extra recipe flags]
#
# --gpu-groups: space-separated groups of comma-separated GPU ids, one group per replica, e.g.
#   "0,1 2,3" = two TP=2 replicas on a 4-GPU host.   Default: one GPU per replica, all GPUs.
# Whether DP (replicas) or TP (one instance) is right is a PER-WORKLOAD, measured decision:
# see docs/topology.md and tests/aiperf/compare-topologies.py. This script only builds the DP side.
# Requires the recipe to honour <PREFIX>_GPUS/_TP/_PORT/_CONTAINER (all precision recipes do).
# Exit: 0 all ready | 1 a replica died | 2 timeout | 3 usage
# ---------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/common.sh"
RECIPE=""; PFX=""; SERVED=""; REPLICAS=""; GROUPS_ARG=""; TP=1; EXTRA=()
while [[ $# -gt 0 ]]; do case "$1" in
  --recipe) RECIPE="$2"; shift 2;; --env-prefix) PFX="$2"; shift 2;; --served) SERVED="$2"; shift 2;;
  --replicas) REPLICAS="$2"; shift 2;; --gpu-groups) GROUPS_ARG="$2"; shift 2;; --tp) TP="$2"; shift 2;;
  --) shift; EXTRA=("$@"); break;;
  *) if ds_common_flag "$@"; then shift "${DS_SHIFT}"; else echo "unknown $1" >&2; exit 3; fi;; esac; done
: "${RECIPE:?--recipe}" "${PFX:?--env-prefix}" "${SERVED:?--served}"
[[ -x "${RECIPE}" ]] || { echo "recipe not executable: ${RECIPE}" >&2; exit 3; }

if [[ -z "${GROUPS_ARG}" ]]; then
  NGPU="$(nvidia-smi -L 2>/dev/null | wc -l)"; REPLICAS="${REPLICAS:-$(( NGPU / TP ))}"
  (( REPLICAS >= 1 )) || { echo "no GPUs visible / replicas=0" >&2; exit 3; }
  g=(); for ((i = 0; i < REPLICAS; i++)); do grp=""; for ((k = 0; k < TP; k++)); do grp+="${grp:+,}$((i * TP + k))"; done; g+=("${grp}"); done
  GROUPS_ARG="${g[*]}"
fi
read -ra GRP <<<"${GROUPS_ARG}"
FRONT="${DS_BASE_PORT}"
PORTS=(); CONTS=(); DRYF=(); [[ "${DS_DRY_RUN}" == 1 ]] && DRYF=(--dry-run)
ds_log "front door :${FRONT}; ${#GRP[@]} replicas from :$((FRONT + 1)) pinned to GPU groups: ${GRP[*]}"
for i in "${!GRP[@]}"; do
  port=$((FRONT + 1 + i)); grp="${GRP[$i]}"; tp=$(awk -F, '{print NF}' <<<"${grp}")
  cname="dp-${PFX,,}-${port}"
  PORTS+=("${port}"); CONTS+=("${cname}")
  env "${PFX}_GPUS=device=${grp}" "${PFX}_TP=${tp}" "${PFX}_PORT=${port}" "${PFX}_CONTAINER=${cname}" \
      "${RECIPE}" --no-wait --no-monitoring ${DRYF[@]+"${DRYF[@]}"} --bind 127.0.0.1 ${EXTRA[@]+"${EXTRA[@]}"} || exit 3
done
[[ "${DS_DRY_RUN}" == 1 ]] && { echo "[dry-run] would wait for ${CONTS[*]} then start LiteLLM on :${FRONT}"; exit 0; }
DS_BIND_ADDR=127.0.0.1; ds_env_args
for i in "${!CONTS[@]}"; do ds_monitoring_up "${CONTS[$i]}" "${PORTS[$i]}" "${CONTS[$i]}" || true; done
for i in "${!CONTS[@]}"; do
  ds_wait_ready "${CONTS[$i]}" "${PORTS[$i]}" "${SERVED}" "${DS_WAIT_TIMEOUT}" || exit $?
done
ds_log "all ${#CONTS[@]} replicas ready; starting LiteLLM front door"
BACK=(); for p in "${PORTS[@]}"; do BACK+=(--backend "127.0.0.1:${p}"); done
DS_BIND_ADDR="${DESKSIDE_BIND_ADDR:-0.0.0.0}" "${HERE}/litellm.sh" up --served "${SERVED}" --port "${FRONT}" "${BACK[@]}"
