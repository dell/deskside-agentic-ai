#!/usr/bin/env bash
# Dispatch a repo script to Landscape-enrolled devices WITHOUT pre-staging the repository: recipes/, scripts/ and monitoring/
# travel inside the Landscape script and are unpacked to /opt/deskside-agentic-ai-solutions-for-nvidia on the device first.
#   scripts/landscape/stage-and-run.sh --ids "ID1,ID2" --cmd "bash scripts/landscape/deploy-solution.sh" \
#       [--env "SOLUTION=hermes NEMOCLAW_INSTALLER_SHA256=<sha>"] [--limit 3000] [--user root]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$HERE/../.."; IDS=""; CMD=""; ENVS=""; LIMIT=3000; RUNAS=root
while [ $# -gt 0 ]; do case "$1" in --ids) IDS="$2"; shift 2;; --cmd) CMD="$2"; shift 2;; --env) ENVS="$2"; shift 2;;
  --limit) LIMIT="$2"; shift 2;; --user) RUNAS="$2"; shift 2;; *) echo "unknown $1" >&2; exit 3;; esac; done
[ -n "$IDS" ] && [ -n "$CMD" ] || { echo "need --ids and --cmd" >&2; exit 3; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
tar -C "$ROOT" --exclude='__pycache__' -czf "$W/repo.tgz" recipes scripts monitoring
{ echo '#!/bin/bash'; echo 'set -uo pipefail; D=/opt/deskside-agentic-ai-solutions-for-nvidia; mkdir -p $D'
  echo "echo '$(base64 -w0 "$W/repo.tgz")' | base64 -d | tar xz -C \$D && chmod -R a+rX \$D"
  echo "cd \$D && export REPO_DIR=\$D ${ENVS} && exec ${CMD}"; } > "$W/payload.sh"
python3 "$HERE/landscape_client.py" runscript --file "$W/payload.sh" --ids "$IDS" --user "$RUNAS" --limit "$LIMIT"
