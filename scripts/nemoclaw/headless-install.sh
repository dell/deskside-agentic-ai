#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Agent-safe / headless alternative to the interactive NemoClaw path
# (`curl ... | bash` + interactive `nemoclaw onboard`).
#
# Three explicit phases with machine-readable outcomes -- never prompts:
#   fetch   download the installer to a file and verify a pinned sha256
#           (no pipe-to-shell). Without a pin it prints the hash and REFUSES
#           unless --trust-on-first-use.
#   install run the verified installer, then `nemoclaw onboard` ONLY if an answers
#           file is supplied (fed on stdin). Otherwise exit 10 = HUMAN STEP REQUIRED
#           (the wizard is interactive); re-run with `wire` afterwards.
#   wire    non-interactive OpenShell wiring using the commands documented in the
#           NemoClaw guides: provider -> inference -> (optional) sandbox -> status.
#
# Exit codes: 0 ok | 10 human step required | 11 installer hash mismatch/unpinned
#             12 prerequisite missing | 13 wiring failed | 3 usage
# Env: NEMOCLAW_NON_INTERACTIVE=1 (use the installer's --non-interactive mode; also set NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1
#      and, to pin the release, NEMOCLAW_INSTALL_REF=<sha> / NEMOCLAW_INSTALL_TAG as documented by the installer)
#      NEMOCLAW_INSTALLER_URL (default https://www.nvidia.com/nemoclaw.sh)
#      NEMOCLAW_INSTALLER_SHA256 (pin)   NEMOCLAW_ONBOARD_ANSWERS (file)
#      LLM_BASE_URL (default http://host.docker.internal:8000/v1)  LLM_MODEL (served name)
#      SANDBOX_NAME  SANDBOX_POLICY (path)  DESKSIDE_DRY_RUN=1
# The fetch/verify/hand-off logic is generic; the `nemoclaw`/`openshell` command lines are the ones documented in this
# repo's NemoClaw guides, so confirm them against the NemoClaw release you install.
# ---------------------------------------------------------------------------
set -euo pipefail
URL="${NEMOCLAW_INSTALLER_URL:-https://www.nvidia.com/nemoclaw.sh}"
PIN="${NEMOCLAW_INSTALLER_SHA256:-}"
ANS="${NEMOCLAW_ONBOARD_ANSWERS:-}"
LLM_BASE_URL="${LLM_BASE_URL:-http://host.docker.internal:8000/v1}"
LLM_MODEL="${LLM_MODEL:-nvidia/nemotron-3.5-lightning}"
SANDBOX_NAME="${SANDBOX_NAME:-}"; SANDBOX_POLICY="${SANDBOX_POLICY:-}"
DRY="${DESKSIDE_DRY_RUN:-0}"; TOFU=0; WORK="${NEMOCLAW_WORKDIR:-$HOME/.deskside/nemoclaw}"
PHASE="${1:-}"; shift || true
while [[ $# -gt 0 ]]; do case "$1" in
  --trust-on-first-use) TOFU=1; shift;; --dry-run) DRY=1; shift;;
  --answers) ANS="$2"; shift 2;; --pin) PIN="$2"; shift 2;;
  *) echo "unknown $1" >&2; exit 3;; esac; done
say() { echo "[nemoclaw-headless] $*" >&2; }
run() { if [[ "${DRY}" == 1 ]]; then printf '[dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi; }
json() { python3 -c 'import json,sys;print(json.dumps(dict(a.split("=",1) for a in sys.argv[1:])))' "$@"; }

fetch() {
  mkdir -p "${WORK}"; local f="${WORK}/nemoclaw-installer.sh" got
  if [[ "${DRY}" == 1 ]]; then echo "[dry-run] curl -fsSL ${URL} -o ${f}; sha256sum ${f} must equal pin ${PIN:-<unset>}"; return 0; fi
  curl -fsSL "${URL}" -o "${f}"; got="$(sha256sum "${f}" | cut -d' ' -f1)"
  if [[ -z "${PIN}" ]]; then
    say "no pin set (NEMOCLAW_INSTALLER_SHA256). installer sha256=${got}"
    (( TOFU )) || { say "refusing to run an unpinned installer; review ${f}, then pin the hash or pass --trust-on-first-use"; json status=unpinned sha256="${got}" file="${f}"; exit 11; }
  elif [[ "${got}" != "${PIN}" ]]; then
    say "HASH MISMATCH expected ${PIN} got ${got}"; json status=hash-mismatch expected="${PIN}" got="${got}"; exit 11
  fi
  json status=fetched sha256="${got}" file="${f}"
}

install_() {
  command -v docker >/dev/null || { say "docker missing"; exit 12; }
  fetch
  if [[ -n "${ANS}" ]]; then
    [[ -r "${ANS}" || "${DRY}" == 1 ]] || { say "answers file ${ANS} unreadable"; exit 12; }
    run bash "${WORK}/nemoclaw-installer.sh"
    say "feeding onboarding answers from ${ANS} on stdin"
    if [[ "${DRY}" == 1 ]]; then echo "[dry-run] nemoclaw onboard < ${ANS}"; else nemoclaw onboard < "${ANS}"; fi
    json status=installed-and-onboarded
  elif [[ "${NEMOCLAW_NON_INTERACTIVE:-0}" == 1 ]]; then
    # NVIDIA's installer has its own non-interactive mode (env/defaults, no wizard); the third-party-software
    # notice must be accepted explicitly by the operator: export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1.
    args=(--non-interactive); [[ "${NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE:-0}" == 1 ]] && args+=(--yes-i-accept-third-party-software)
    run bash "${WORK}/nemoclaw-installer.sh" "${args[@]}"
    json status=installed-noninteractive
  else
    run bash "${WORK}/nemoclaw-installer.sh"
    say "HUMAN STEP REQUIRED: 'nemoclaw onboard' is interactive. Run it once in a terminal (choose the agent), then: $0 wire"
    json status=human-step-required next="nemoclaw onboard" then="$0 wire"
    exit 10
  fi
}

wire() {
  command -v openshell >/dev/null || [[ "${DRY}" == 1 ]] || { say "openshell not found (run install + onboard first)"; exit 12; }
  run openshell provider create --name vllm-local --type openai --credential OPENAI_API_KEY=local --config "base_url=${LLM_BASE_URL}" || { json status=wiring-failed step=provider; exit 13; }
  run openshell inference set --provider vllm-local --model "${LLM_MODEL}" || { json status=wiring-failed step=inference; exit 13; }
  if [[ -n "${SANDBOX_NAME}" ]]; then
    [[ -n "${SANDBOX_POLICY}" ]] || { say "SANDBOX_POLICY required with SANDBOX_NAME"; exit 12; }
    run openshell sandbox create "${SANDBOX_NAME}" --policy "${SANDBOX_POLICY}" || { json status=wiring-failed step=sandbox; exit 13; }
  fi
  if [[ "${DRY}" == 1 ]]; then echo "[dry-run] openshell status  # expect: Connected"; json status=dry-run; return 0; fi
  openshell status | grep -qi connected && json status=wired model="${LLM_MODEL}" base_url="${LLM_BASE_URL}" || { json status=wiring-failed step=status; exit 13; }
}

case "${PHASE}" in
  fetch) fetch;; install) install_;; wire) wire;;
  *) sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 3;;
esac
