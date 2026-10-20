#!/usr/bin/env bash
# Build the UDPcast sender/receiver from the pinned upstream source (needs gcc + make; no root unless PREFIX needs it).
# The distro package (20120424) can abort large transfers ("Buffer overflow in produce msg:free-queue"), so use this build.
#   scripts/multicast/udpcast-build.sh [PREFIX=/opt/udpcast]     -> PREFIX/bin/udp-sender, PREFIX/bin/udp-receiver
# amd64 hosts can alternatively use upstream's udpcast_20250223_amd64.deb; there is no arm64 deb, hence this script.
set -euo pipefail
PREFIX="${1:-${PREFIX:-/opt/udpcast}}"; VER=20250223
URL="https://www.udpcast.linux.lu/download/udpcast-${VER}.tar.gz"
SHA="cefd7554c877e1bc76987d2b96b23f7699a2e5340c254454f61b6e0dae370aa7"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
curl -fsSL "$URL" -o "$W/u.tgz"
echo "${SHA}  $W/u.tgz" | sha256sum -c - >/dev/null || { echo "udpcast tarball hash mismatch" >&2; exit 11; }
tar xzf "$W/u.tgz" -C "$W"; cd "$W/udpcast-${VER}"
./configure >/dev/null && make udp-sender udp-receiver >/dev/null   # skip the man-page step (needs perl)
mkdir -p "$PREFIX/bin"; install -m 0755 udp-sender udp-receiver "$PREFIX/bin/"
echo "installed $PREFIX/bin/udp-sender and udp-receiver (udpcast ${VER})"
