#!/usr/bin/env bash
# Health assessment for Nemotron 3.5 Lightning on Dell Precision towers (T2/T4/T6) -- field-debug wrapper around lib/health.sh.
# Usage: $0 [--container NAME] [--port PORT] [--served NAME] [--tool-test] [--no-smoke] [--json] [--bundle [DIR]]
# Defaults mirror the recipe (same env vars). Read-only apart from one tiny completion.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../lib/common.sh"
source "${HERE}/../../lib/health.sh"

H_PORT="${NEMOTRON_LIGHTNING_PORT:-}"
H_CONTAINER="${NEMOTRON_LIGHTNING_CONTAINER:-}"
H_CONTAINER_PREFIX="lightning-3.5-precision-"
H_SERVED="nvidia/nemotron-3.5-lightning"
recipe_checks() {
  local tp; tp="$(docker inspect -f "{{join .Args \" \"}}" "${H_CONTAINER}" 2>/dev/null | grep -o "tensor-parallel-size [0-9]*" | awk "{print \$2}")"
  if [[ "${tp:-1}" -gt 1 ]]; then
    docker inspect -f "{{join .Args \" \"}}" "${H_CONTAINER}" | grep -q disable-custom-all-reduce \
      && h_add PASS tp-allreduce "TP=${tp} with custom all-reduce disabled (PCIe-safe)" \
      || h_add WARN tp-allreduce "TP=${tp} without --disable-custom-all-reduce" "PCIe-only RTX PRO towers crash here: set NEMOTRON_LIGHTNING_DISABLE_CUSTOM_AR=1 and re-run"
  fi
  return 0
}
ds_health_main "$@"
