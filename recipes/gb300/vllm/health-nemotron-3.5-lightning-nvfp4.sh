#!/usr/bin/env bash
# Health assessment for Nemotron 3.5 Lightning on GB300 -- field-debug wrapper around lib/health.sh.
# Usage: $0 [--container NAME] [--port PORT] [--served NAME] [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
# Defaults mirror the recipe (same env vars). Read-only apart from one tiny completion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../lib/common.sh"
source "${HERE}/../../lib/health.sh"

H_PORT="${NEMOTRON_LIGHTNING_PORT:-}"
H_CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-}"
H_CONTAINER_PREFIX="vllm_"
H_SERVED="nvidia/nemotron-3.5-lightning"
recipe_checks() {
  nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -q GB300 \
    && h_add PASS gb300-gpu "GB300 visible (recipe UUID-pins it)" || h_add FAIL gb300-gpu "no GB300 in nvidia-smi" "recipe auto-detects the GB300 UUID; set NEMOTRON_LIGHTNING_GPU_UUID"
  return 0
}
ds_health_main "$@"
