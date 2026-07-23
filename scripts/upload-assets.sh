#!/usr/bin/env bash
# upload-assets.sh - package + upload the two large runtime assets Uncork fetches
# on demand, so slim builds and fresh Steam installs work end to end. Mirrors the
# URLs already wired in the code:
#   wine-cef  -> WINE_CEF_URL            (lib.sh)            release tag: wine-cef
#   steam     -> STEAM_CLIENT_SNAPSHOT_URL (setup-steam.sh)  release tag: steam-client
#
# Requirements: the GitHub CLI `gh`, authenticated with write access to the repo
# (default PapaRascal2020/uncork). Install: `brew install gh` then `gh auth login`.
#
# Usage:
#   scripts/upload-assets.sh all        # both assets
#   scripts/upload-assets.sh wine-cef   # just wine-cef
#   scripts/upload-assets.sh steam      # just the Steam client snapshot
#
# Override the repo with UNCORK_REPO=owner/name.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${UNCORK_REPO:-PapaRascal2020/uncork}"
DATA="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}"
WHAT="${1:-all}"

command -v gh >/dev/null || { echo "!! gh (GitHub CLI) not found. brew install gh && gh auth login" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "!! gh is not authenticated. Run: gh auth login" >&2; exit 1; }

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT

# Create the release for a tag if it does not exist yet, then upload (clobber).
publish() { # <tag> <title> <file>
  local tag="$1" title="$2" file="$3"
  gh release view "$tag" --repo "$REPO" >/dev/null 2>&1 \
    || gh release create "$tag" --repo "$REPO" --title "$title" --notes "Uncork runtime asset. Uploaded by upload-assets.sh." >/dev/null
  echo "==> Uploading $(basename "$file") ($(du -h "$file" | cut -f1)) to $REPO@$tag"
  gh release upload "$tag" "$file" --repo "$REPO" --clobber
  echo "    done: https://github.com/$REPO/releases/download/$tag/$(basename "$file")"
}

pack_wine_cef() {
  local src="$ROOT/engine/wine-cef"
  [[ -x "$src/wswine.bundle/bin/wine" ]] || { echo "!! engine/wine-cef/wswine.bundle not found." >&2; return 1; }
  local out="$STAGE/wine-cef.tar.gz"
  echo "==> Packing wine-cef (wswine.bundle at archive root)…"
  tar -czf "$out" -C "$src" .          # wswine.bundle lands at the archive root
  publish "wine-cef" "Uncork wine-cef" "$out"
}

pack_steam() {
  local snap="$DATA/engine/steam-client-snapshot"
  [[ -d "$snap/package" ]] || { echo "!! Steam snapshot not found at $snap (with package/)." >&2; return 1; }
  local out="$STAGE/steam-client-snapshot.tar.gz"
  echo "==> Packing the Steam client snapshot (~2 GB, this takes a while)…"
  # setup-steam.sh extracts in the PARENT and expects a top-level
  # steam-client-snapshot/ dir, so pack it by name from its parent.
  tar -czf "$out" -C "$(dirname "$snap")" "$(basename "$snap")"
  publish "steam-client" "Uncork Steam client snapshot" "$out"
}

case "$WHAT" in
  wine-cef) pack_wine_cef ;;
  steam)    pack_steam ;;
  all)      pack_wine_cef; pack_steam ;;
  *) echo "usage: upload-assets.sh [all|wine-cef|steam]" >&2; exit 2 ;;
esac
echo "==> Assets uploaded. Slim builds (UNCORK_SLIM=1) and fresh Steam installs will now fetch them."
