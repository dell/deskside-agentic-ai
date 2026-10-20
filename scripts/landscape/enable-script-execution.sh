#!/bin/bash
# Enable Canonical Landscape remote script execution on a client (run on the
# device, with sudo, once). After this + one client exchange (~4 min), the
# fleet scripts in this folder can be dispatched remotely via
# landscape_client.py runscript.
#
# NOTE 1: --silent is REQUIRED for headless/ssh runs (the interactive wizard
#         otherwise aborts with "EOF when reading a line").
# NOTE 2: on an ALREADY-REGISTERED machine this RE-REGISTERS it: the computer
#         gets a NEW id and may sit PENDING approval in the Landscape UI
#         (acceptance is UI-only on SaaS). Prefer running this during initial
#         enrollment; afterwards check:
#           landscape_client.py get GetPendingComputers
set -euo pipefail
ACCOUNT="${1:-${LANDSCAPE_ACCOUNT:-}}"
if [ -z "$ACCOUNT" ]; then
    echo "usage: $0 <landscape-account-name>   (or set LANDSCAPE_ACCOUNT)" >&2
    exit 2
fi
# The CLI ships with the landscape-client package, which is NOT always
# present even when a dormant landscape-client.service unit is (that one
# comes from landscape-common). Install it if missing.
if ! command -v landscape-config >/dev/null 2>&1; then
    echo "landscape-client package missing — installing:"
    sudo apt-get update -qq >/dev/null 2>&1 || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq landscape-client
fi
# NOTE 3: on a FRESH machine (no /etc/landscape/client.conf yet), silent mode
#         also requires --computer-title, or it aborts with "An account name
#         and computer title are required."
sudo landscape-config --silent \
    --account-name="$ACCOUNT" \
    --computer-title="${COMPUTER_TITLE:-$(hostname)}" \
    --include-manager-plugins=ScriptExecution \
    --script-users=root,landscape
sudo systemctl daemon-reload 2>/dev/null || true
sudo systemctl restart landscape-client
echo "OK: ScriptExecution enabled on $(hostname)."
echo "    If this machine was already registered, verify it is Accepted in the"
echo "    Landscape UI (Computers > Pending) before automating against it."
