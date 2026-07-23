#!/usr/bin/env bash
# ensure-wine-engine.sh - make a core Wine engine present, downloading it into the
# writable per-user engine dir if a slim build omitted it from the payload. This is
# the same "big binary fetched, not bundled" pattern as ensure-engine.sh (GPTk) and
# ensure-wine-build.sh (Wine Downloader), applied to the two core engines:
#
#   wine-stable : the default engine every game uses. Public Gcenx build (WINE_URL).
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
    # Already there? (bundled payload or a prior download resolved by lib.sh)
    if [[ -x "$WINE_HOME/bin/wine" ]]; then ok "wine-stable already present."; exit 0; fi
    dest="$UNCORK_DATA_DIR/engine/wine-stable"
    step 5 "Downloading Wine (stable)…"
    tb="$CACHE/wine-stable.tar.xz"
    curl -L --fail --progress-bar "$WINE_URL" -o "$tb" || die "Couldn't download Wine from $WINE_URL"
    step 70 "Extracting Wine…"
    rm -rf "$dest"; mkdir -p "$dest"
    tar -xf "$tb" --strip-components="$WINE_ARCHIVE_STRIP" -C "$dest" "$WINE_ARCHIVE_SUBTREE" \
      || die "Extraction failed (check WINE_ARCHIVE_SUBTREE/STRIP in lib.sh)."
    rm -f "$tb"
    [[ -x "$dest/bin/wine" ]] || die "Extracted, but $dest/bin/wine is missing."
    step 100 "Wine (stable) ready."; ok "Installed wine-stable into ${dest#"$UNCORK_DATA_DIR"/}." ;;

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
