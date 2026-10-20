#!/bin/bash
# Fix: `docker run --runtime=nvidia` fails with
#   "unknown or invalid runtime name: nvidia"
# on stock DGX Spark / Ubuntu images where the NVIDIA Container Toolkit is
# absent or never registered with the docker daemon.
# Run as root (e.g. dispatched via Landscape ScriptExecution).
set -uo pipefail
echo "== runtimes before:"
docker info 2>/dev/null | grep -iA1 "Runtimes:" || echo "(no custom runtimes)"
echo "== running containers (docker restart will restart nothing but do cycle the daemon):"
docker ps --format "{{.Names}} {{.Status}}" | head -5
if ! command -v nvidia-ctk >/dev/null 2>&1; then
    echo "== installing nvidia-container-toolkit:"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>&1 | tail -1
    apt-get install -y -qq nvidia-container-toolkit 2>&1 | tail -2
fi
nvidia-ctk --version | head -1
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
# A fixed short sleep races daemon warm-up and yields a false FIX-FAILED on
# slow boots; poll until the daemon answers AND lists the runtime (90s cap).
echo "== waiting for docker daemon + nvidia runtime (up to 90s):"
ok=0
for i in $(seq 1 30); do
    sleep 3
    docker info >/dev/null 2>&1 || continue
    docker info 2>/dev/null | grep -q "Runtimes:.*nvidia" && { ok=1; break; }
done
echo "== runtimes after:"
docker info 2>/dev/null | grep -iA1 "Runtimes:"
nvidia-smi -L | head -1
[ "$ok" = 1 ] && echo "FIX-OK" || { echo "FIX-FAILED: nvidia runtime still missing"; exit 1; }
