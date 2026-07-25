#!/usr/bin/env bash
# ensure-engine-bundle.sh: download + install an Uncork Wine engine bundle on demand.
#
# Reads the engine's download URL + sha256 from wine-fixes/engines.json and fetches
# it into engine/<id> if not already present (with live @@STEP@@ progress). This is
# how a clean install pulls the pre-compiled, known-good engines (Ubisoft/EA CEF
# engines, etc.): the packaged counterpart to scripts/package-engine.sh.
#
# Usage:  scripts/ensure-engine-bundle.sh <engine-id>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ID="${1:?usage: ensure-engine-bundle.sh <engine-id>}"
CATALOG="$PROJECT_ROOT/wine-fixes/engines.json"
DEST_DIR="$ENGINE_DIR"                 # engine/ (writable data dir at runtime)
mkdir -p "$DEST_DIR"

# Already installed? (a bundled/prebuilt engine present in engine/ is fine too)
if [[ -d "$DEST_DIR/$ID" || -d "$DEST_DIR/wine-cef" && "$ID" == uncork-1.0-wine-9.0 ]]; then
  ok "Engine '$ID' already present."; exit 0
fi

read_json() { py -c "import json,sys;d=json.load(open('$CATALOG'));print(d['engines'].get('$ID',{}).get('download',{}).get('$1','') or '')" 2>/dev/null; }
URL="$(read_json url)"; SHA="$(read_json sha256)"
[[ -n "$URL" ]] || die "No download URL for engine '$ID' in engines.json (upload the bundle + set download.url)."

tb="$(mktemp -d)/$ID.tar.gz"
step 3 "Downloading engine $ID…"
preflight_network
preflight_disk 3
download_progress "$URL" "$tb" 5 88 "Downloading $ID…" || die "Couldn't download engine '$ID'."
if [[ -n "$SHA" ]]; then
  got="$(shasum -a 256 "$tb" | awk '{print $1}')"
  [[ "$got" == "$SHA" ]] || die "Checksum mismatch for '$ID' (got $got, want $SHA)."
  ok "Checksum verified."
fi
step 90 "Installing $ID…"
tar -xzf "$tb" -C "$DEST_DIR" || die "Couldn't unpack engine '$ID'."
rm -f "$tb"
step 100 "Engine $ID ready."
ok "Installed engine '$ID' into ${DEST_DIR#$PROJECT_ROOT/}."
