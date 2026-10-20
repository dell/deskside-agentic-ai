#!/usr/bin/env bash
# Health assessment for Qwen3.8-Flash-Next NVFP4 on Dell Precision -- field-debug wrapper around lib/health.sh.
# Usage: $0 [--container NAME] [--port PORT] [--served NAME] [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
# Defaults mirror the recipe (same env vars). Read-only apart from one tiny completion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../lib/common.sh"
source "${HERE}/../../lib/health.sh"

H_PORT="${FLASHNEXT_PORT:-}"
H_CONTAINER="${FLASHNEXT_CONTAINER:-flashnext-m-precision}"
H_SERVED="qwen3.8-flash-next"
recipe_checks() {
  local gib; gib="$(awk "/MemTotal/{printf \"%d\",\$2/1048576}" /proc/meminfo)"
  (( gib < 128 )) && h_add FAIL engram-host-ram "${gib} GiB host RAM; engram CPU offload needs >= 128 GB" "add RAM or use Lightning instead" || h_add PASS engram-host-ram "${gib} GiB host RAM (>=128 needed)"
  return 0
}
ds_health_main "$@"
