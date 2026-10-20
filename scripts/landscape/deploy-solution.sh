#!/bin/bash
# Fleet deploy payload for the solutions that sit on top of a serving recipe (dispatched as root via Landscape
# ScriptExecution). It runs the serving payload first, then the solution-specific step, and ends with a hard gate:
# Landscape reports exit 0 as "succeeded", so this script exits non-zero unless the solution is actually up.
#
#   SOLUTION   openclaw | hermes | vss | higher-ed          (required)
#   REPO_DIR   repo location on the target                    (default /opt/deskside-agentic-ai-solutions-for-nvidia)
#   SKIP_SERVING=1  skip the serving recipe (it is already running)
#   Serving payload variables (RECIPE, CONTAINER, IMAGE, HF_HOME, ...) are passed through; see deploy-serving-recipe.sh.
#   openclaw|hermes : NEMOCLAW_INSTALLER_SHA256 (pin, required)  AGENT_USER (default dell)  LLM_MODEL (default: first served model)
#                     SANDBOX_NAME  DESKSIDE_API_KEY  NEMOCLAW_INSTALL_REF (pin the NemoClaw release)
#   vss             : VSS_COMPOSE_FILE (compose project of the VSS blueprint)  VSS_HEALTH_URL (default http://localhost:7777)
#   higher-ed       : COURSE_COMPOSE (course profile compose file)
set -uo pipefail
SOLUTION="${SOLUTION:?set SOLUTION=openclaw|hermes|vss|higher-ed}"
REPO_DIR="${REPO_DIR:-/opt/deskside-agentic-ai-solutions-for-nvidia}"
export REPO_DIR
PORT="${DESKSIDE_BASE_PORT:-8000}"

if [ "${SKIP_SERVING:-0}" != 1 ]; then
  echo "== serving (plane 1)"; bash "$REPO_DIR/scripts/landscape/deploy-serving-recipe.sh" || { echo "SERVING FAILED"; exit 1; }
fi
# the VSS blueprint brings its own LLM/VLM, so only the other solutions need the local endpoint
[ "$SOLUTION" = vss ] || curl -sf "http://localhost:${PORT}/v1/models" >/dev/null || { echo "ENDPOINT NOT READY on :${PORT}"; exit 1; }

wait_url() { for _ in $(seq 1 60); do curl -sfI "$1" >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }

case "$SOLUTION" in
  openclaw|hermes)
    echo "== agent runtime (plane 2)"
    : "${NEMOCLAW_INSTALLER_SHA256:?pin the installer hash (NEMOCLAW_INSTALLER_SHA256)}"
    AGENT_USER="${AGENT_USER:-dell}"      # the account that owns the runtime (needs Docker access: usermod -aG docker <user>)
    MODEL="${LLM_MODEL:-$(curl -s -m10 "http://localhost:${PORT}/v1/models" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null)}"
    [ -n "$MODEL" ] || { echo "no served model found on :${PORT}"; exit 1; }
    id -nG "$AGENT_USER" | grep -qw docker || usermod -aG docker "$AGENT_USER"
    # NemoClaw's own non-interactive onboarding: point it at the local OpenAI-compatible endpoint the recipe serves.
    su - "$AGENT_USER" -c "cd $REPO_DIR && NEMOCLAW_INSTALLER_SHA256='$NEMOCLAW_INSTALLER_SHA256' NEMOCLAW_NON_INTERACTIVE=1 NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 \
      NEMOCLAW_AGENT=$([ "$SOLUTION" = hermes ] && echo hermes || echo openclaw) NEMOCLAW_SANDBOX_NAME='${SANDBOX_NAME:-my-assistant}' \
      NEMOCLAW_PROVIDER=custom NEMOCLAW_ENDPOINT_URL='http://localhost:${PORT}/v1' NEMOCLAW_MODEL='$MODEL' COMPATIBLE_API_KEY='${DESKSIDE_API_KEY:-local}' \
      timeout 2400 bash scripts/nemoclaw/headless-install.sh install" 2>&1 | tail -40
    [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "NEMOCLAW INSTALL/ONBOARD FAILED"; exit 1; }
    su - "$AGENT_USER" -c 'export PATH=$HOME/.local/bin:$PATH; openshell sandbox list' 2>&1 | grep -q Ready \
      && echo "DEPLOY-OK: ${SOLUTION} sandbox Ready on ${MODEL}" || { echo "SANDBOX NOT READY"; exit 1; } ;;
  vss)
    : "${VSS_COMPOSE_FILE:?set VSS_COMPOSE_FILE}"
    echo "== VSS blueprint"; docker compose -f "$VSS_COMPOSE_FILE" up -d || { echo "COMPOSE FAILED"; exit 1; }
    wait_url "${VSS_HEALTH_URL:-http://localhost:7777}" && echo "DEPLOY-OK: VSS up" || { echo "VSS NOT HEALTHY"; docker compose -f "$VSS_COMPOSE_FILE" ps; exit 1; } ;;
  higher-ed)
    : "${COURSE_COMPOSE:?set COURSE_COMPOSE}"
    echo "== course profile"; docker compose -f "$COURSE_COMPOSE" up -d || { echo "COMPOSE FAILED"; exit 1; }
    sleep 5; [ -z "$(docker compose -f "$COURSE_COMPOSE" ps --status running -q)" ] && { echo "COURSE STACK NOT UP"; exit 1; }
    echo "DEPLOY-OK: course profile up" ;;
  *) echo "unknown SOLUTION=$SOLUTION"; exit 3 ;;
esac
