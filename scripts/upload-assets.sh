#!/usr/bin/env bash
# upload-assets.sh - package + upload the large runtime engines Uncork fetches on
# demand, so slim builds work end to end. Mirrors the URLs already wired in code:
#   wine-stable -> WINE_STABLE_ASSET_URL  (lib.sh)            release tag: wine-stable
#   wine-cef  -> WINE_CEF_URL            (lib.sh)            release tag: wine-cef
#
# NOTE: we deliberately do NOT publish a Steam client asset. Redistributing Valve's
# client binaries is not permitted by the Steam Subscriber Agreement, so Uncork
# installs Steam from Valve's official installer on the user's machine instead (see
# setup-steam.sh). Do not add a Steam packer here.
#
# Requirements: the GitHub CLI `gh`, authenticated with write access to the repo
# (default PapaRascal2020/uncork). Install: `brew install gh` then `gh auth login`.
#
# Usage:
#   scripts/upload-assets.sh all          # all assets
#   scripts/upload-assets.sh wine-stable  # just the DXMT wine-stable engine
#   scripts/upload-assets.sh wine-cef     # just wine-cef
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

# Pin each asset's SHA-256 so the app can verify a download is EXACTLY our engine
# (see verify_asset_sha in lib.sh). Written here at publish time so the pin can never
# drift from the uploaded bytes. Commit scripts/asset-checksums.env after uploading.
CKSUM_FILE="$ROOT/scripts/asset-checksums.env"
record_checksum() {  # <KEY> <file>
  local key="$1" file="$2" sha
  sha="$(shasum -a 256 "$file" | awk '{print $1}')"
  touch "$CKSUM_FILE"
  grep -v "^${key}=" "$CKSUM_FILE" > "$CKSUM_FILE.tmp" 2>/dev/null || true
  mv "$CKSUM_FILE.tmp" "$CKSUM_FILE" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$sha" >> "$CKSUM_FILE"
  echo "    pinned $key=$sha (scripts/asset-checksums.env; commit this)"
}

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
  record_checksum WINE_STABLE_SHA256 "$out"
  publish "wine-stable" "Uncork wine-stable (DXMT)" "$out"
}

pack_wine_cef() {
  local src="$ROOT/engine/wine-cef"
  [[ -x "$src/wswine.bundle/bin/wine" ]] || { echo "!! engine/wine-cef/wswine.bundle not found." >&2; return 1; }
  local out="$STAGE/wine-cef.tar.gz"
  echo "==> Packing wine-cef (wswine.bundle at archive root)…"
  tar -czf "$out" -C "$src" .          # wswine.bundle lands at the archive root
  record_checksum WINE_CEF_SHA256 "$out"
  publish "wine-cef" "Uncork wine-cef" "$out"
}

case "$WHAT" in
  wine-stable) pack_wine_stable ;;
  wine-cef) pack_wine_cef ;;
  all)      pack_wine_stable; pack_wine_cef ;;
  *) echo "usage: upload-assets.sh [all|wine-stable|wine-cef]" >&2; exit 2 ;;
esac
echo "==> Assets uploaded. Slim builds (UNCORK_SLIM=1) will now fetch them."
