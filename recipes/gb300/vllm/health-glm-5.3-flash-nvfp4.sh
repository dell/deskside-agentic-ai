#!/usr/bin/env bash
# Health assessment for GLM-5.3-Flash NVFP4 on GB300 -- field-debug wrapper around lib/health.sh.
# Usage: $0 [--container NAME] [--port PORT] [--served NAME] [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
# Defaults mirror the recipe (same env vars). Read-only apart from one tiny completion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../lib/common.sh"
source "${HERE}/../../lib/health.sh"

H_PORT="${GLM53_PORT:-}"
H_CONTAINER="${GLM53_CONTAINER:-glm53-flash-gb300}"
H_SERVED="glm-5.3-flash"
recipe_checks() {
  local img; img="$(docker inspect -f "{{.Config.Image}}" "${H_CONTAINER}" 2>/dev/null)"
  [[ "${img}" == *glm53-flash-arm64* ]] && h_add PASS glm-image "${img}" || h_add WARN glm-image "${img:-unknown}" "GLM-5.3 needs the day-0 arm64 build; older tags reject glm5_next"
  return 0
}
ds_health_main "$@"
