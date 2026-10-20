#!/usr/bin/env bash
# Distribute a directory (golden image, model cache, datasets) to many Landscape-enrolled systems at once over LAN multicast.
#   multicast-distribute.sh --ids "ID1 ID2 ..." --sender-host HOST --src PATH --dest DIR --bin-dir DIR
#                           [--extra-receivers N] [--max-wait SEC] [--sender-iface IF] [--max-bitrate 900m] [--no-results]
# 1. builds a receiver payload (receiver script + the UDPcast binaries for the targets' architecture) and dispatches it with
#    Landscape ScriptExecution (needs LANDSCAPE_* credentials; targets must have script execution enabled);
# 2. starts the sender on HOST (the image / model-proxy server, wired, same VLAN); it waits until every receiver has joined,
#    so Landscape's dispatch lag does not matter, then streams once to all of them;
# 3. polls Landscape for each target's MULTICAST-RECEIVED line and compares its sha256 with the sender's.
# --bin-dir holds udp-sender and udp-receiver built for the TARGET architecture (scripts/multicast/udpcast-build.sh).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; LC="$HERE/../landscape/landscape_client.py"
IDS=""; SH=""; SRC=""; DEST=""; BIN=""; EXTRA=0; MAXW=7200; SIF=""; RATE=""; RES=1
while [ $# -gt 0 ]; do case "$1" in --ids) IDS="$2"; shift 2;; --sender-host) SH="$2"; shift 2;; --src) SRC="$2"; shift 2;; --dest) DEST="$2"; shift 2;;
  --bin-dir) BIN="$2"; shift 2;; --extra-receivers) EXTRA="$2"; shift 2;; --max-wait) MAXW="$2"; shift 2;; --sender-iface) SIF="$2"; shift 2;;
  --max-bitrate) RATE="$2"; shift 2;; --no-results) RES=0; shift;; *) echo "unknown $1" >&2; exit 3;; esac; done
for v in IDS SH SRC DEST BIN; do [ -n "${!v}" ] || { echo "missing --$(echo "$v" | tr 'A-Z' 'a-z')" >&2; exit 3; }; done
[ -x "$BIN/udp-sender" ] && [ -x "$BIN/udp-receiver" ] || { echo "no udp-sender/udp-receiver in $BIN" >&2; exit 3; }
N=$(( $(wc -w <<<"$IDS") + EXTRA ))
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# --- receiver payload (self-contained: binaries + script travel inside the Landscape script) ---
tar -C "$BIN" -czf "$W/bin.tgz" udp-sender udp-receiver; cp "$HERE/multicast-receive.sh" "$W/"
tar -C "$W" -czf "$W/pkg.tgz" multicast-receive.sh
{
  echo '#!/bin/bash'; echo 'set -uo pipefail; D=/opt/udpcast; mkdir -p $D/bin'
  echo "echo '$(base64 -w0 "$W/bin.tgz")' | base64 -d | tar xz -C \$D/bin"
  echo "echo '$(base64 -w0 "$W/pkg.tgz")' | base64 -d | tar xz -C \$D"
  echo "exec bash \$D/multicast-receive.sh --dest '$DEST' --bin \$D/bin --start-timeout $MAXW"
} > "$W/payload.sh"
echo "== dispatching receivers to: $IDS"
OUT="$(python3 "$LC" runscript --file "$W/payload.sh" --ids "$(tr ' ' ',' <<<"$IDS")" --user root --limit "$((MAXW + 600))" 2>&1)"; echo "$OUT" | tail -3
GROUP="$(grep -o '"id": [0-9]*' <<<"$OUT" | head -1 | grep -o '[0-9]*')"

# --- sender on the server ---
SD="~/udpcast"; ssh -o BatchMode=yes "$SH" "mkdir -p $SD/bin"
# copy under temporary names then rename, so binaries that are running (a local receiver) are replaced safely
scp -q "$BIN/udp-sender" "$BIN/udp-receiver" "$HERE/multicast-send.sh" "$SH:udpcast/bin/"
ssh -o BatchMode=yes "$SH" "cd udpcast && mv -f bin/multicast-send.sh ./multicast-send.sh"
echo "== sender on $SH waits for $N receivers (max-wait ${MAXW}s)"
SOUT="$(ssh -o BatchMode=yes "$SH" "bash $SD/multicast-send.sh --src $SRC --receivers $N --max-wait $MAXW --bin $SD/bin ${SIF:+--iface $SIF} ${RATE:+--max-bitrate $RATE}" 2>&1 | tr '\r' '\n' | tail -3)" || true; echo "$SOUT" | tail -2
grep -q MULTICAST-SENT <<<"$SOUT" || { echo "SENDER FAILED"; exit 1; }
WANT="$(grep -o 'sha256=[0-9a-f]*' <<<"$SOUT" | tail -1 | cut -d= -f2)"
[ "$RES" = 1 ] || exit 0

# --- collect Landscape results ---
echo "== waiting for Landscape results (group ${GROUP:-?}); results can lag by an hour"
python3 "$LC" pollscript --group "$GROUP" --timeout "${POLL_TIMEOUT:-5400}" 2>&1 | tee "$W/res.txt" | tail -30
BAD=0; for L in $(grep -o 'sha256=[0-9a-f]*' "$W/res.txt" | cut -d= -f2); do [ "$L" = "$WANT" ] || BAD=1; done
grep -q MULTICAST-RECEIVED "$W/res.txt" || BAD=1
[ "$BAD" = 0 ] && echo "ALL RECEIVERS MATCH sha256=$WANT" || { echo "MISMATCH OR MISSING RESULTS (sender sha256=$WANT)"; exit 2; }
