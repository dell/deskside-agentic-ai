#!/usr/bin/env bash
# Send a directory (or one file) to every waiting receiver at once over LAN multicast (UDPcast).
#   multicast-send.sh --src PATH --receivers N [--iface IF] [--max-wait SEC] [--max-bitrate 900m] [--bin DIR]
# Waits until N receivers have joined (or --max-wait after the first one), streams a tar of PATH, and prints the
# stream sha256 so receivers can verify. Run it on the image / model-proxy server, on the lab VLAN, wired.
set -euo pipefail
SRC=""; N=1; IF=""; MAXW=3600; RATE="${MAX_BITRATE:-}"; BIN="${UDPCAST_BIN:-/opt/udpcast/bin}"
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift 2;; --receivers) N="$2"; shift 2;; --iface) IF="$2"; shift 2;;
  --max-wait) MAXW="$2"; shift 2;; --max-bitrate) RATE="$2"; shift 2;; --bin) BIN="$2"; shift 2;; *) echo "unknown $1" >&2; exit 3;; esac; done
[ -e "$SRC" ] || { echo "no such path: $SRC" >&2; exit 3; }
[ -n "$IF" ] || IF="$(ip route | awk '/default/{print $5; exit}')"
SHAF="$(mktemp)"; T0=$(date +%s)
if [ -d "$SRC" ]; then TAR=(tar -C "$SRC" --sort=name -cf - .); else TAR=(tar -C "$(dirname "$SRC")" --sort=name -cf - "$(basename "$SRC")"); fi
"${TAR[@]}" | tee >(sha256sum | cut -d' ' -f1 > "$SHAF") \
  | "$BIN/udp-sender" --interface "$IF" --nokbd --file /dev/stdin --min-receivers "$N" --max-wait "$MAXW" ${RATE:+--max-bitrate "$RATE"}
sleep 1
echo "MULTICAST-SENT sha256=$(cat "$SHAF") receivers=$N seconds=$(( $(date +%s) - T0 ))"
rm -f "$SHAF"
