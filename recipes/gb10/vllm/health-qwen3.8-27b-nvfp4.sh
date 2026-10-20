#!/usr/bin/env bash
# Health assessment for Qwen3.8-27B NVFP4 (MTP) on GB10 -- field-debug wrapper around lib/health.sh.
# Usage: $0 [--container NAME] [--port PORT] [--served NAME] [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
# Defaults mirror the recipe (same env vars). Read-only apart from one tiny completion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../lib/common.sh"
source "${HERE}/../../lib/health.sh"

H_PORT="${QWEN38_27B_PORT:-}"
H_CONTAINER="${QWEN38_27B_CONTAINER:-qwen38-27b-gb10}"
H_SERVED="qwen3.8-27b"
recipe_checks() {
  h_add WARN gb10-mem-util "recipe pins --gpu-memory-utilization 0.9 of 128 GB unified memory" "if host memory pressure appears, edit the recipe to ~0.7"
  return 0
}
ds_health_main "$@"
