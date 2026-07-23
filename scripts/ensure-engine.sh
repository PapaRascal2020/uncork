#!/usr/bin/env bash
# ensure-engine.sh: download the graphics engine (GPTk Wine + D3DMetal) ON
# DEMAND the first time a user sets up a launcher. This is what lets the shipped
# app be lean: Wine + D3DMetal aren't bundled, the setup wizard fetches them
# here. Idempotent: no-ops if already installed. Emits @@STEP@@ progress.
#
# The Gcenx game-porting-toolkit Wine (LGPL, redistributable) already bundles a
# working Apple D3DMetal, so nothing from Apple's Developer site is needed.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"   # GPTK_ROOT / GPTK_WINE (writable dir)

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

GPTK_URL="${GPTK_URL:-https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz}"
# GPTK_ROOT + GPTK_WINE come from gptk.sh (writable per-user engine dir).

if [[ -x "$GPTK_WINE" && -d "$GPTK_DIR/lib/external/D3DMetal.framework" ]]; then
  step 100 "Graphics engine ready."
  ok "GPTk Wine + D3DMetal already installed."
  exit 0
fi

step 2 "Checking your Mac…"
require_arm64
require_rosetta

step 5 "Downloading the graphics engine (Wine + D3DMetal, ~240 MB)…"
mkdir -p "$GPTK_ROOT"
tarball="$GPTK_ROOT/gptk-wine.tar.xz"
download_progress "$GPTK_URL" "$tarball" 5 88 "Downloading Wine + D3DMetal…" \
  || die "Couldn't download the graphics engine. Check your connection and retry."

step 90 "Installing the graphics engine…"
( cd "$GPTK_ROOT" && tar -xf "gptk-wine.tar.xz" ) || die "Couldn't unpack the graphics engine."
rm -f "$tarball"

[[ -x "$GPTK_WINE" && -d "$GPTK_DIR/lib/external/D3DMetal.framework" ]] \
  || die "Engine install looks incomplete (no D3DMetal). Please retry."

step 100 "Graphics engine ready (Wine + D3DMetal)."
ok "GPTk Wine + D3DMetal installed: $GPTK_WINE"
