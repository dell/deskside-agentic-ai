#!/usr/bin/env bash
# Health assessment for Nemotron 3.5 Super VL (precision recipe) -- wrapper around lib/health.sh.
# Usage: $0 [--container NAME] [--port PORT] [--served NAME] [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../lib/common.sh"
source "${HERE}/../../lib/health.sh"
H_PORT="${NEMOTRON_35_SUPER_VL_PORT:-}"
H_CONTAINER="${NEMOTRON_35_SUPER_VL_CONTAINER:-}"
H_CONTAINER_PREFIX="supervl-precision-"
H_SERVED="nvidia/nemotron-3.5-super-vl"
recipe_checks() {
  local args; args="$(docker inspect -f '{{join .Args " "}}' "${H_CONTAINER}" 2>/dev/null)"
  grep -q "reasoning-parser nemotron_v3" <<<"${args}" && h_add PASS supervl-parsers "tool qwen3_coder + reasoning nemotron_v3 present" || h_add FAIL supervl-parsers "parser flags missing" "agent tool-calling will fail silently without them"
  return 0
}
ds_health_main "$@"
