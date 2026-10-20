#!/bin/bash
# Fleet deploy payload (dispatched as root via Landscape ScriptExecution):
# ensure the docker nvidia runtime and the recipe's image exist, then launch
# a serving recipe from this repo on the target. The recipe runs detached;
# the model itself downloads to the HF cache on first boot.
#
# Configure per fleet via environment (baked into the dispatched copy or
# exported here):
#   RECIPE     recipe path on the target   (default: repo's GB10 Lightning recipe)
#   REPO_DIR   repo location on the target (default: /opt/deskside-agentic-ai-solutions-for-nvidia)
#   IMAGE      image override consumed by the recipe (e.g. NEMOTRON_LIGHTNING_IMAGE=<tag>)
#   CONTAINER  container name the recipe creates (docker ps filter for the gate)
#   HF_HOME    HF cache to mount (a root-context script does NOT see /home/<user>)
#   FIX_SCRIPT path to fix-docker-nvidia-runtime.sh on the target (defaults:
#              next to this script, else the synced repo copy under REPO_DIR)
set -uo pipefail
REPO_DIR="${REPO_DIR:-/opt/deskside-agentic-ai-solutions-for-nvidia}"
RECIPE="${RECIPE:-$REPO_DIR/recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh}"
[ -f "$REPO_DIR/recipes/lib/common.sh" ] && . "$REPO_DIR/recipes/lib/common.sh"
IMG="${IMAGE:-$(ds_image lightning 2>/dev/null || echo vllm/vllm-openai:nightly)}"   # pinned per recipes/versions.lock
CONTAINER="${CONTAINER:-lightning-3.5-gb10}"
export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"

# 1) nvidia runtime must be valid (self-heal; see fix-docker-nvidia-runtime.sh).
# When dispatched by Landscape this script runs from a temp location, so the
# fix script lives next to the SYNCED REPO copy — check both.
docker info 2>/dev/null | grep -q "Runtimes:.*nvidia" || {
    echo "nvidia runtime missing — applying fix:"
    FIX="${FIX_SCRIPT:-$(dirname "$0")/fix-docker-nvidia-runtime.sh}"
    [ -f "$FIX" ] || FIX="$REPO_DIR/scripts/landscape/fix-docker-nvidia-runtime.sh"
    [ -f "$FIX" ] || { echo "FIX SCRIPT NOT FOUND (set FIX_SCRIPT)"; exit 1; }
    bash "$FIX" || exit 1
}

# 2) pre-pull: recipes cap their own `docker pull` at 60s by design, so a cold
#    cache needs the image pulled here first (cache hit inside the recipe).
echo "== ensure image ($IMG):"
docker image inspect "$IMG" >/dev/null 2>&1 || docker pull "$IMG" 2>&1 | tail -2
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "IMAGE MISSING"; exit 1; }

# 3) run the recipe (bash explicitly: never assume exec bits survived rsync)
echo "== run recipe: $RECIPE"
cd "$(dirname "$RECIPE")"
# The recipe now blocks until the endpoint is truly ready (readiness contract:
# exit 0 ready | 1 died | 2 timeout). Keep its budget under the Landscape --limit.
export DESKSIDE_WAIT_TIMEOUT="${DESKSIDE_WAIT_TIMEOUT:-1500}"
bash "./$(basename "$RECIPE")" > /tmp/deploy-recipe.log 2>&1
RC=$?
tail -6 /tmp/deploy-recipe.log
[ "$RC" -eq 0 ] || { echo "RECIPE FAILED rc=$RC (1=died 2=timeout 3=usage)"; exit 1; }
docker ps -a --filter "name=$CONTAINER" --format "{{.Names}} {{.Status}}"

# HARD GATE: never end cosmetically — Landscape reports script exit 0 as
# "succeeded" even when the serving launch failed several lines earlier.
[ -n "$(docker ps -q --filter "name=^/${CONTAINER}$")" ] \
    && echo "DEPLOY-OK: container up" || { echo "CONTAINER NOT UP"; exit 1; }
