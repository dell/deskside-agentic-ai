#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Print client configs (OpenCode, Codex, Continue, Claude Code, Copilot CLI) whose
# context/output limits are derived from the RUNNING recipe's actual window
# (/v1/models max_model_len), so agent clients never request more than the server
# serves (a 200K window vs clients asking for 32K outputs and
# 100K+ contexts fails with opaque 400s / compaction loops).
#
#   recipes/lib/client-config.sh --port 8000 --served nvidia/nemotron-3.5-lightning [--host HOST] [--tool opencode|codex|continue|claude|copilot|all]
#   (--max-model-len N to compute without a live server)
# Rule: max_output = min(16384, window/8) rounded to 512 (>=512); prompt budget = window - max_output - 1024.
# Config KEY NAMES come from each client's docs and are not validated against a client
# binary here -- check them against your installed version (see ide-integration.md).
# ---------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/common.sh"
HOST=localhost; PORT=8000; SERVED=""; TOOL=all; N=""
while [[ $# -gt 0 ]]; do case "$1" in
  --host) HOST="$2"; shift 2;; --port) PORT="$2"; shift 2;; --served) SERVED="$2"; shift 2;;
  --tool) TOOL="$2"; shift 2;; --max-model-len) N="$2"; shift 2;;
  -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0;; *) echo "unknown $1" >&2; exit 3;; esac; done
: "${SERVED:?--served required}"
if [[ -z "${N}" ]]; then
  N="$(curl -s -m 10 "http://${HOST}:${PORT}/v1/models" | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]; print(next((m.get("max_model_len") for m in d if m["id"]==sys.argv[1]), 0))' "${SERVED}")" || N=0
fi
[[ "${N:-0}" -gt 0 ]] || { echo "could not read max_model_len from http://${HOST}:${PORT}/v1/models for ${SERVED}" >&2; exit 1; }
read -r OUT PROMPT <<<"$(ds_client_limits "${N}")"
BASE="http://${HOST}:${PORT}"
echo "# window=${N}  max_output=${OUT}  prompt_budget=${PROMPT}   (served=${SERVED})"
show() { [[ "${TOOL}" == all || "${TOOL}" == "$1" ]]; }
if show opencode; then cat <<E1

## OpenCode  ~/.config/opencode/config.json  (models.<id>.limit)
{"\$schema":"https://opencode.ai/config.json","provider":{"dell-deskside-agentic":{"npm":"@ai-sdk/openai-compatible","name":"Dell deskside (local vLLM)",
 "options":{"baseURL":"${BASE}/v1","apiKey":"local"},
 "models":{"${SERVED}":{"name":"${SERVED}","limit":{"context":${N},"output":${OUT}}}}}},"model":"dell-deskside-agentic/${SERVED}"}
E1
fi
if show codex; then cat <<E2

## Codex  ~/.codex/config.toml
model_provider = "deskside"
model = "${SERVED}"
model_context_window = ${N}
model_max_output_tokens = ${OUT}
model_auto_compact_token_limit = ${PROMPT}
[model_providers.deskside]
name = "Dell Deskside vLLM"
base_url = "${BASE}/v1"
env_key = "DESKSIDE_API_KEY"
wire_api = "responses"
E2
fi
if show continue; then cat <<E3

## Continue  ~/.continue/config.yaml  (use a non-reasoning model for autocomplete if you serve one)
models:
  - name: ${SERVED} (local vLLM)
    provider: openai
    model: ${SERVED}
    apiBase: ${BASE}/v1
    apiKey: local
    roles: [chat, edit, apply]
    defaultCompletionOptions: {contextLength: ${N}, maxTokens: ${OUT}}
E3
fi
if show claude; then cat <<E4

## Claude Code  (env)  -- requires the server to expose the Anthropic Messages API (/v1/messages); verify on your pinned vLLM build
export ANTHROPIC_BASE_URL="${BASE}"
export ANTHROPIC_AUTH_TOKEN="local"
export ANTHROPIC_MODEL="${SERVED}"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=${OUT}
# Claude Code assumes a large window; compact early so history stays inside ${N} tokens:
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=$(( PROMPT * 100 / N ))
E4
fi
if show copilot; then cat <<E5

## GitHub Copilot CLI (BYOK)  -- the *_MAX_* variable names below follow the BYOK docs; verify on your CLI version
export COPILOT_PROVIDER_BASE_URL="${BASE}/v1"
export COPILOT_PROVIDER_API_KEY="local"
export COPILOT_MODEL="${SERVED}"
export COPILOT_PROVIDER_MAX_PROMPT_TOKENS=${PROMPT}
export COPILOT_PROVIDER_MAX_OUTPUT_TOKENS=${OUT}
E5
fi
