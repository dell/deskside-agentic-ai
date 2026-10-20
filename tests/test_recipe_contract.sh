#!/usr/bin/env bash
# Exercises recipes/lib/common.sh (readiness contract + monitoring wiring) with a
# GPU-free mock server -- safe on any Docker host, even one whose GPUs are busy.
#   ready path -> READY line, rc 0, Prometheus target 'up'
#   died path  -> rc 1 + diagnosis ; timeout path -> rc 2 ; --no-wait -> rc 0 fast
# Uses its own container names, alt ports and a temp monitoring dir; cleans up.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${MOCK_IMAGE:-vllm/vllm-openai:nightly}"   # any image with python3; entrypoint overridden
export DESKSIDE_MON_DIR="$(mktemp -d)" DESKSIDE_WAIT_INTERVAL=1
PASS=0; FAIL=0
ok()  { echo "PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL  $1  ($2)"; FAIL=$((FAIL+1)); }
cleanup() { docker rm -f dstest-ready dstest-die dstest-never dstest-nowait dstest-b1 dstest-b2 dstest-litellm >/dev/null 2>&1
  "${ROOT}/recipes/lib/monitoring.sh" down >/dev/null 2>&1; docker volume rm deskside-prometheus-data deskside-grafana-data >/dev/null 2>&1
  rm -rf "${DESKSIDE_MON_DIR}"; }
trap cleanup EXIT

# fake_recipe NAME PORT READY_AFTER DIE_AFTER [recipe flags...]; prints recipe stdout+stderr; rc via global RC
fake_recipe() {
  local name="$1" port="$2" ra="$3" die="$4"; shift 4
  out="$(bash -c '
    set -euo pipefail; source "$1/recipes/lib/common.sh"; shift
    name=$1 port=$2 ra=$3 die=$4 img=$5 mock=$6; shift 6
    while [[ $# -gt 0 ]]; do if ds_common_flag "$@"; then shift "$DS_SHIFT"; else echo "bad flag $1"; exit 3; fi; done
    ds_rm "$name"
    ds_docker run -d --name "$name" -p "$port:8000" -e MOCK_MODEL=mock/model -e MOCK_READY_AFTER="$ra" -e MOCK_DIE_AFTER="$die" \
       -v "$mock:/mock.py:ro" --entrypoint python3 "$img" /mock.py >/dev/null
    ds_finish "$name" "$port" mock/model "$name"
  ' _ "${ROOT}" "$name" "$port" "$ra" "$die" "${IMG}" "${ROOT}/tests/lib/mock_vllm.py" "$@" 2>&1)"; RC=$?
}

fake_recipe dstest-ready 18101 6 0
[[ $RC -eq 0 ]] && ok "ready path rc=0" || bad "ready path rc" "rc=$RC"
grep -q '^READY {"ready":true,"container":"dstest-ready","port":18101' <<<"$out" && ok "READY line emitted" || bad "READY line" "$out"
grep -q "tokenomics dashboard" <<<"$out" && ok "dashboard URL printed" || bad "dashboard URL" "$out"
PP="$(docker inspect -f '{{index .Config.Labels "deskside.port"}}' deskside-prometheus 2>/dev/null)"
sleep 12
h="$(curl -s -m 5 "127.0.0.1:${PP}/api/v1/targets" | python3 -c "import json,sys;print([t['health'] for t in json.load(sys.stdin)['data']['activeTargets'] if t['labels'].get('container')=='dstest-ready'])" 2>/dev/null)"
[[ "$h" == "['up']" ]] && ok "prometheus scrapes recipe target (up)" || bad "prometheus target" "$h"
GP="$(docker inspect -f '{{index .Config.Labels "deskside.port"}}' deskside-grafana 2>/dev/null)"
[[ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -u "admin:$(cat "${DESKSIDE_MON_DIR}/grafana-admin-password")" "127.0.0.1:${GP}/api/dashboards/uid/deskside-tokenomics")" == 200 ]] \
  && ok "grafana tokenomics dashboard provisioned" || bad "grafana dashboard" "port $GP"
"${ROOT}/recipes/lib/health.sh" --container dstest-ready --port 18101 --served mock/model --json >/tmp/dstest-health.json 2>&1
python3 -c "import json;d=json.load(open('/tmp/dstest-health.json'));import sys;sys.exit(0 if d['fail']==0 else 1)" && ok "generic health.sh against mock: 0 FAIL" || bad "health.sh" "$(head -c 300 /tmp/dstest-health.json)"

fake_recipe dstest-die 18102 60 3 --no-monitoring
[[ $RC -eq 1 ]] && ok "container death rc=1" || bad "death rc" "rc=$RC"
grep -q "HINT: out of memory" <<<"$out" && ok "death diagnosis hint" || bad "diagnosis hint" "$out"

fake_recipe dstest-never 18103 -1 0 --no-monitoring --wait-timeout 8
[[ $RC -eq 2 ]] && ok "timeout rc=2" || bad "timeout rc" "rc=$RC"

fake_recipe dstest-nowait 18104 30 0 --no-monitoring --no-wait
[[ $RC -eq 0 ]] && grep -q NOT-WAITING <<<"$out" && ok "--no-wait returns immediately" || bad "--no-wait" "rc=$RC $out"

# --- LiteLLM front door over two replicas (skipped when the router image cannot be pulled) ---
LLM_IMG="$(bash -c "source ${ROOT}/recipes/lib/common.sh; ds_image litellm" 2>/dev/null)"
if docker image inspect "${LLM_IMG}" >/dev/null 2>&1 || timeout 120 docker pull "${LLM_IMG}" >/dev/null 2>&1; then
  fake_recipe dstest-b1 18201 0 0 --no-monitoring; fake_recipe dstest-b2 18202 0 0 --no-monitoring
  export DESKSIDE_LITELLM_DIR="${DESKSIDE_MON_DIR}/litellm"
  out="$(DESKSIDE_WAIT_TIMEOUT=240 "${ROOT}/recipes/lib/litellm.sh" up --served mock/model --port 18200 --name dstest-litellm --workers 2 --backend 127.0.0.1:18201 --backend 127.0.0.1:18202 2>&1)"; RC=$?
  [[ $RC -eq 0 ]] && grep -q '^READY .*"port":18200' <<<"$out" && ok "litellm front door READY over 2 replicas" || bad "litellm up" "rc=$RC $(tail -3 <<<"$out")"
  r="$(curl -s -m 30 -H "Authorization: Bearer $(cat ${DESKSIDE_LITELLM_DIR}/master-key)" localhost:18200/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"mock/model","messages":[{"role":"user","content":"hi"}],"max_tokens":8}')"
  grep -q reasoning_content <<<"$r" && ok "request routed through litellm to a replica" || bad "litellm routing" "$r"
  docker stop dstest-b1 >/dev/null; sleep 2; fails=0
  for i in 1 2 3 4 5 6; do curl -s -m 30 -H "Authorization: Bearer $(cat ${DESKSIDE_LITELLM_DIR}/master-key)" localhost:18200/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"mock/model","messages":[{"role":"user","content":"hi"}],"max_tokens":8}' | grep -q reasoning_content || fails=$((fails+1)); done
  [[ $fails -eq 0 ]] && ok "failover: 6/6 requests succeed with one replica down" || bad "failover" "$fails/6 failed"
else echo "SKIP  litellm tests (image ${LLM_IMG} unavailable)"; fi

echo "---- recipe contract: ${PASS} passed, ${FAIL} failed ----"; exit $((FAIL > 0))
