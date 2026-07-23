#!/usr/bin/env bash
# package-engine.sh - package a built Wine engine into an uploadable bundle.
#
# Produces dist/<engine-id>-<version>.tar.gz + .sha256 so you can upload it to a
# release host (e.g. GitHub Releases on the Uncork repo). The app/scripts then
# download it on demand (see ensure-engine-bundle.sh + wine-fixes/engines.json).
#
# Each engine ships as a known-good, versioned, reproducible artifact: a launcher
# pre-compiled with working Wine and libraries.
#
# Usage:  scripts/package-engine.sh <engine-id> [engine-dir]
#   e.g.  scripts/package-engine.sh uncork-1.0-wine-9.0 engine/wine-cef
#         scripts/package-engine.sh wine-stable
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:?usage: package-engine.sh <engine-id> [engine-dir]}"
SRC="${2:-$ROOT/engine/${ID}}"
# common aliases
[[ ! -d "$SRC" && "$ID" == uncork-1.0-wine-9.0 ]] && SRC="$ROOT/engine/wine-cef"
[[ -d "$SRC" ]] || { echo "engine dir not found: $SRC"; exit 1; }

DIST="$ROOT/dist"; mkdir -p "$DIST"
OUT="$DIST/${ID}.tar.gz"
echo "==> Packaging $ID from ${SRC#$ROOT/} → ${OUT#$ROOT/}"
# reproducible-ish, exclude test prefixes/caches; gzip = curl|tar xzf everywhere
tar --exclude='*/.git' --exclude='*/dosdevices' -C "$(dirname "$SRC")" -czf "$OUT" "$(basename "$SRC")"
( cd "$DIST" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
SZ=$(du -h "$OUT" | awk '{print $1}')
SHA=$(awk '{print $1}' "$OUT.sha256")
echo "==> Done: ${OUT#$ROOT/}  ($SZ)"
echo "    sha256: $SHA"
echo
echo "NEXT: upload dist/${ID}.tar.gz to your release host, then set its URL + sha256"
echo "      for engine '$ID' in wine-fixes/engines.json (\"download\": {...})."
echo "      The app downloads it via ensure-engine-bundle.sh on first use."
