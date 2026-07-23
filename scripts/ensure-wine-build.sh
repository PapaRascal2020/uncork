#!/usr/bin/env bash
# ensure-wine-build.sh: download + install a standalone Wine build on demand for
# Uncork's Wine Manager ("Wine Builds" tab). Fetches the Gcenx macOS Wine tarball
# named in wine-fixes/wine-builds.json and extracts its wine tree into
# engine/wine-builds/<id>/ (bin/lib/share). Streams @@STEP@@ progress.
#
# Usage:  ensure-wine-build.sh <build-id>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ID="${1:?usage: ensure-wine-build.sh <build-id>}"
CATALOG="$PROJECT_ROOT/wine-fixes/wine-builds.json"
# Install into the WRITABLE per-user data dir (the payload engine dir is read-only
# in a shipped .app), exactly like ensure-profile.sh does for D3DMetal engines.
DATA_ROOT="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}"
DEST="$DATA_ROOT/engine/wine-builds/$ID"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

# already installed?
if [[ -x "$DEST/bin/wine" ]]; then step 100 "$ID already installed."; ok "Wine build '$ID' already present."; exit 0; fi

read_json() { python3 -c "import json,sys;d=json.load(open('$CATALOG'));print(d['builds'].get('$ID',{}).get('$1','') or '')" 2>/dev/null; }
URL="$(read_json url)"; SUBTREE="$(read_json archive_subtree)"; NAME="$(read_json name)"
[[ -n "$URL" ]] || die "No download URL for wine build '$ID' in wine-builds.json."

CACHE="${UNCORK_CACHE:-$DATA_ROOT/cache}"
mkdir -p "$CACHE" "$DATA_ROOT/engine/wine-builds"
TB="$CACHE/$ID.tar.xz"

step 5 "Downloading ${NAME:-$ID}…"
if [[ ! -s "$TB" ]]; then
  curl -sL "$URL" -o "$TB.part" &
  CURL=$!
  total=$(curl -sIL "$URL" | awk 'tolower($0) ~ /content-length/ {print $2}' | tr -d '\r' | tail -1)
  while kill -0 "$CURL" 2>/dev/null; do
    if [[ -n "$total" && "$total" -gt 0 && -f "$TB.part" ]]; then
      have=$(stat -f%z "$TB.part" 2>/dev/null || echo 0)
      pct=$(( 5 + have * 70 / total ))   # download spans 5→75%
      step "$pct" "Downloading ${NAME:-$ID}… $(( have/1048576 ))/$(( total/1048576 )) MB"
    fi
    sleep 1
  done
  wait "$CURL" || { rm -f "$TB.part"; die "Download failed for '$ID'."; }
  mv "$TB.part" "$TB"
fi

step 80 "Extracting…"
TMP="$(mktemp -d)"
tar -xJf "$TB" -C "$TMP" || die "Couldn't unpack '$ID'."
# locate the wine tree: prefer the declared subtree, else find bin/wine
SRC="$TMP/$SUBTREE"
if [[ ! -x "$SRC/bin/wine" ]]; then
  SRC="$(dirname "$(dirname "$(find "$TMP" -type f -path '*/bin/wine' 2>/dev/null | head -1)")")"
fi
[[ -x "$SRC/bin/wine" ]] || die "No wine binary found inside the '$ID' archive."

step 92 "Installing → engine/wine-builds/$ID…"
rm -rf "$DEST"; mkdir -p "$DEST"
# copy the wine tree contents (bin/lib/share) into DEST
( cd "$SRC" && tar -cf - . ) | ( cd "$DEST" && tar -xf - )
rm -rf "$TMP"; rm -f "$TB"
xattr -cr "$DEST" 2>/dev/null || true

[[ -x "$DEST/bin/wine" ]] || die "Install of '$ID' failed (no bin/wine)."
step 100 "${NAME:-$ID} ready."
ok "Installed wine build '$ID' → ${DEST#$PROJECT_ROOT/}."
