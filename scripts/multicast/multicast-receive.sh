#!/usr/bin/env bash
# Receive a multicast stream from multicast-send.sh and unpack it into DEST (dispatched to lab systems via Landscape).
#   multicast-receive.sh --dest DIR [--iface IF] [--start-timeout SEC] [--expect-sha SHA] [--bin DIR]
# Exit: 0 ok (and sha matched when --expect-sha is given) | 1 transfer failed | 2 checksum mismatch
set -euo pipefail
DEST=""; IF=""; ST=7200; EXP=""; BIN="${UDPCAST_BIN:-/opt/udpcast/bin}"
while [ $# -gt 0 ]; do case "$1" in --dest) DEST="$2"; shift 2;; --iface) IF="$2"; shift 2;; --start-timeout) ST="$2"; shift 2;;
  --expect-sha) EXP="$2"; shift 2;; --bin) BIN="$2"; shift 2;; *) echo "unknown $1" >&2; exit 3;; esac; done
[ -n "$DEST" ] || { echo "--dest required" >&2; exit 3; }
[ -n "$IF" ] || IF="$(ip route | awk '/default/{print $5; exit}')"
mkdir -p "$DEST"; SHAF="$(mktemp)"; T0=$(date +%s)
if "$BIN/udp-receiver" --interface "$IF" --nokbd --file /dev/stdout --start-timeout "$ST" | tee >(sha256sum | cut -d' ' -f1 > "$SHAF") | tar -xf - -C "$DEST"; then OK=1; else OK=0; fi
sleep 1; GOT="$(cat "$SHAF")"; SECS=$(( $(date +%s) - T0 ))
echo "MULTICAST-RECEIVED host=$(hostname) iface=$IF sha256=$GOT seconds=$SECS dest=$DEST bytes=$(du -sb "$DEST" | cut -f1)"
[ "$OK" = 1 ] || { echo "TRANSFER FAILED"; exit 1; }
[ -z "$EXP" ] || [ "$EXP" = "$GOT" ] || { echo "CHECKSUM MISMATCH (expected $EXP)"; exit 2; }
