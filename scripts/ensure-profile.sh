#!/usr/bin/env bash
# ensure-profile.sh: download a compatibility PROFILE's engine on demand, the
# Mac analog of Steam fetching a Proton version. Idempotent: no-ops if the engine
# is already installed. Emits @@STEP@@ progress. Only d3dmetal profiles that carry
# a `download` URL + `engine_id` in compat/profiles.json need this; bundled ones
# (auto, wine11-*) are always present.
#
# Usage: ensure-profile.sh <profile-id>       (e.g. gptk-2.1)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

prof="${1:?usage: ensure-profile.sh <profile-id>}"
label="$(profile_get "$prof" label)"; [[ -n "$label" ]] || label="$prof"
engine_id="$(profile_get "$prof" engine_id)"
url="$(profile_get "$prof" download)"

# Nothing to download for bundled/no-engine profiles: treat as ready.
if [[ -z "$engine_id" || -z "$url" ]]; then
  step 100 "$label is ready."
  ok "Profile '$prof' needs no download."
  exit 0
fi

ENG_ROOT="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/engine/$engine_id"
WINE64="$ENG_ROOT/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
D3DM="$ENG_ROOT/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework"

if [[ -x "$WINE64" && -d "$D3DM" ]]; then
  step 100 "$label already installed."
  ok "Engine '$engine_id' already present."
  exit 0
fi

step 3 "Preparing to download $label…"
require_arm64
require_rosetta
mkdir -p "$ENG_ROOT"
tb="$ENG_ROOT/engine.tar.xz"

step 5 "Downloading $label…"
download_progress "$url" "$tb" 5 88 "Downloading $label…" \
  || die "Couldn't download $label. Check your connection and retry."

step 90 "Installing $label…"
( cd "$ENG_ROOT" && tar -xf "$tb" ) || die "Couldn't unpack $label."
rm -f "$tb"

[[ -x "$WINE64" && -d "$D3DM" ]] || die "$label install looks incomplete (no D3DMetal). Please retry."
step 100 "$label ready."
ok "Engine '$engine_id' installed for profile '$prof'."
