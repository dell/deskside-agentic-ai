#!/usr/bin/env bash
# Health assessment for Nemotron 3.5 Lightning on GB10 -- field-debug wrapper around lib/health.sh.
# Usage: $0 [--container NAME] [--port PORT] [--served NAME] [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
# Defaults mirror the recipe (same env vars). Read-only apart from one tiny completion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../lib/common.sh"
source "${HERE}/../../lib/health.sh"

H_PORT="${NEMOTRON_LIGHTNING_PORT:-}"
H_CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-lightning-3.5-gb10}"
H_SERVED="nvidia/nemotron-3.5-lightning"
recipe_checks() {
  local procs; procs="$(nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader 2>/dev/null | grep -vc "^$" || true)"
  (( procs > 1 )) && h_add WARN gb10-gpu-squatters "${procs} GPU processes (unified memory is shared with CPU)" "nvidia-smi: stop ollama/llama-server/bench workers that are not this container"
  return 0
}
ds_health_main "$@"
