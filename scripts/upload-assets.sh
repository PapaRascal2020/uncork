#!/usr/bin/env bash
# upload-assets.sh - package + upload the two large runtime assets Uncork fetches
# on demand, so slim builds and fresh Steam installs work end to end. Mirrors the
# URLs already wired in the code:
#   wine-stable -> WINE_STABLE_ASSET_URL  (lib.sh)            release tag: wine-stable
#   wine-cef  -> WINE_CEF_URL            (lib.sh)            release tag: wine-cef
#   steam     -> STEAM_CLIENT_SNAPSHOT_URL (setup-steam.sh)  release tag: steam-client
#
# Requirements: the GitHub CLI `gh`, authenticated with write access to the repo
# (default PapaRascal2020/uncork). Install: `brew install gh` then `gh auth login`.
#
# Usage:
#   scripts/upload-assets.sh all          # all assets
#   scripts/upload-assets.sh wine-stable  # just the DXMT wine-stable engine
#   scripts/upload-assets.sh wine-cef     # just wine-cef
#   scripts/upload-assets.sh steam        # just the Steam client snapshot
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

pack_wine_stable() {
  local src="$ROOT/engine/wine-stable"
  [[ -x "$src/bin/wine" ]] || { echo "!! engine/wine-stable/bin/wine not found." >&2; return 1; }
  # Guard against reshipping the bug: our engine must carry DXMT (a ~20 MB d3d11.dll
  # + the winemetal Metal bridge). A stock Gcenx tree has a ~450 KB d3d11 and no
  # winemetal.so, and hosting that would leave every DirectX 11 game broken.
  local d3d11="$src/lib/wine/x86_64-windows/d3d11.dll"
  [[ -f "$src/lib/wine/x86_64-unix/winemetal.so" && -f "$d3d11" && "$(stat -f%z "$d3d11")" -gt 5000000 ]] \
    || { echo "!! engine/wine-stable is not the DXMT engine (small d3d11 / no winemetal.so). Refusing to upload." >&2; return 1; }
  local out="$STAGE/wine-stable.tar.gz"
  echo "==> Packing wine-stable with DXMT (~400 MB, this takes a while)…"
  tar -czf "$out" -C "$src" .          # wine tree (bin/lib/share) lands at the archive root
  publish "wine-stable" "Uncork wine-stable (DXMT)" "$out"
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
  wine-stable) pack_wine_stable ;;
  wine-cef) pack_wine_cef ;;
  steam)    pack_steam ;;
  all)      pack_wine_stable; pack_wine_cef; pack_steam ;;
  *) echo "usage: upload-assets.sh [all|wine-stable|wine-cef|steam]" >&2; exit 2 ;;
esac
echo "==> Assets uploaded. Slim builds (UNCORK_SLIM=1) and fresh Steam installs will now fetch them."
