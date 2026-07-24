#!/usr/bin/env bash
# ensure-wine-engine.sh - make a core Wine engine present, downloading it into the
# writable per-user engine dir if a slim build omitted it from the payload. This is
# the same "big binary fetched, not bundled" pattern as ensure-engine.sh (GPTk) and
# ensure-wine-build.sh (Wine Downloader), applied to the two core engines:
#
#   wine-stable : the default engine every game uses. OUR build with DXMT baked in
#                 (WINE_STABLE_ASSET_URL): the public Gcenx build has no DXMT, so a
#                 slim install that fetched it cannot run DirectX 11 games.
#   wine-cef    : CrossOver-based Wine for CEF launchers (Ubisoft/EA). WINE_CEF_URL.
#
# No-op when the engine is already present (bundled in the payload OR already
# downloaded), so it is safe to call before every launch/setup. Streams @@STEP@@.
#
# Usage: ensure-wine-engine.sh <wine-stable|wine-cef>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

ID="${1:?usage: ensure-wine-engine.sh <wine-stable|wine-cef>}"
CACHE="${UNCORK_CACHE:-$UNCORK_DATA_DIR/cache}"; mkdir -p "$CACHE"

case "$ID" in
  wine-stable)
    # Already there AND has DXMT? (bundled payload, or a prior download of OUR
    # engine, resolved by lib.sh). The winemetal.so bridge is the DXMT marker: a
    # bundled payload always has it; a per-user engine only if it's our asset.
    # An older slim build may have fetched stock Gcenx (no winemetal), which cannot
    # run DirectX 11 games, so we do NOT treat that as present: fall through and
    # (re)download our DXMT engine over it.
    if [[ -x "$WINE_HOME/bin/wine" && -f "$WINE_HOME/lib/wine/x86_64-unix/winemetal.so" ]]; then
      ok "wine-stable (DXMT) already present."; exit 0
    fi
    dest="$UNCORK_DATA_DIR/engine/wine-stable"
    step 5 "Downloading Wine + DirectX (DXMT)…"
    tb="$CACHE/wine-stable.tar.gz"
    curl -L --fail --progress-bar "$WINE_STABLE_ASSET_URL" -o "$tb" \
      || die "Couldn't download wine-stable from $WINE_STABLE_ASSET_URL (host it with: scripts/upload-assets.sh wine-stable)."
    step 70 "Extracting Wine…"
    rm -rf "$dest"; mkdir -p "$dest"
    tar -xf "$tb" -C "$dest" || die "Extraction failed."   # wine tree (bin/lib/share) at archive root
    rm -f "$tb"
    [[ -x "$dest/bin/wine" ]] || die "Extracted, but $dest/bin/wine is missing."
    [[ -f "$dest/lib/wine/x86_64-unix/winemetal.so" ]] \
      || die "Extracted, but winemetal.so (DXMT/DirectX 11 bridge) is missing: the hosted asset is not the DXMT engine."
    step 100 "Wine + DirectX ready."; ok "Installed wine-stable (DXMT) into ${dest#"$UNCORK_DATA_DIR"/}." ;;

  wine-cef)
    for c in "$UNCORK_DATA_DIR/engine/wine-cef/wswine.bundle" "$ENGINE_DIR/wine-cef/wswine.bundle"; do
      [[ -x "$c/bin/wine" ]] && { ok "wine-cef already present."; exit 0; }
    done
    [[ -n "$WINE_CEF_URL" ]] || die "wine-cef is not bundled and WINE_CEF_URL is not set."
    dest="$UNCORK_DATA_DIR/engine/wine-cef"
    step 5 "Downloading Wine (CEF)…"
    tb="$CACHE/wine-cef.tar.gz"
    curl -L --fail --progress-bar "$WINE_CEF_URL" -o "$tb" \
      || die "Couldn't download wine-cef from $WINE_CEF_URL (host the tarball on the release to enable CEF launchers on slim builds)."
    step 70 "Extracting Wine (CEF)…"
    rm -rf "$dest"; mkdir -p "$dest"
    tar -xf "$tb" -C "$dest" || die "Extraction of wine-cef failed."
    rm -f "$tb"
    # Accept a tarball that contains wswine.bundle at any depth; normalize to
    # $dest/wswine.bundle so the lib.sh resolver finds it.
    if [[ ! -x "$dest/wswine.bundle/bin/wine" ]]; then
      found="$(find "$dest" -maxdepth 3 -type d -name wswine.bundle 2>/dev/null | head -1)"
      [[ -n "$found" && "$found" != "$dest/wswine.bundle" ]] && mv "$found" "$dest/wswine.bundle"
    fi
    [[ -x "$dest/wswine.bundle/bin/wine" ]] || die "Extracted, but $dest/wswine.bundle/bin/wine is missing."
    step 100 "Wine (CEF) ready."; ok "Installed wine-cef into ${dest#"$UNCORK_DATA_DIR"/}." ;;

  *) die "Unknown engine '$ID' (expected wine-stable or wine-cef)." ;;
esac
