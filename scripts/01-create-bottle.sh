#!/usr/bin/env bash
# Step 1: bootstrap a Wine bottle (prefix) for the MVP.
#
# What it does:
#   - Verifies Apple Silicon + Rosetta 2
#   - Ensures an x86-64 Wine build is present (downloads if WINE_URL is set)
#   - Initializes a fresh Wine prefix under bottles/<BOTTLE_NAME>
#
# Usage:
#   ./scripts/01-create-bottle.sh
#   WINE_URL="https://.../wine-crossover.tar.gz" ./scripts/01-create-bottle.sh
#
# This step is headless and idempotent: re-running it is safe.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Preflight checks"
require_arm64
require_rosetta
ok "Apple Silicon + Rosetta 2 available"

# --- Ensure Wine is present --------------------------------------------------
if [[ ! -x "$WINE_BIN" ]]; then
  if [[ -z "$WINE_URL" ]]; then
    warn "No Wine build found at $WINE_HOME and WINE_URL is not set."
    cat <<EOF

  Provide an x86-64 macOS Wine build. Two options:

    A) Point WINE_URL at a release tarball (recommended: Gcenx wine-crossover):
         WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/.../wine-crossover-XX.tar.gz" \\
           ./scripts/01-create-bottle.sh

    B) Extract a Wine build yourself so that this binary exists:
         $WINE_BIN

EOF
    die "Wine not available yet."
  fi

  log "Downloading Wine build"
  mkdir -p "$ENGINE_DIR"
  tarball="$ENGINE_DIR/wine-download.tar.xz"
  curl -L --fail --progress-bar "$WINE_URL" -o "$tarball" || die "Download failed: $WINE_URL"

  log "Extracting Wine"
  rm -rf "$WINE_HOME"; mkdir -p "$WINE_HOME"
  # Gcenx builds ship a "Wine Staging.app" bundle; extract only the inner wine
  # tree (bin/lib/share) so it lands directly under WINE_HOME.
  tar -xf "$tarball" --strip-components="$WINE_ARCHIVE_STRIP" -C "$WINE_HOME" "$WINE_ARCHIVE_SUBTREE" \
    || die "Extraction failed. Check WINE_ARCHIVE_SUBTREE / WINE_ARCHIVE_STRIP in lib.sh for this tarball layout."
  rm -f "$tarball"

  [[ -x "$WINE_BIN" ]] || die "Extracted, but $WINE_BIN not found. Check the tarball layout and update WINE_BIN in lib.sh."
fi
ok "Wine present: $WINE_BIN"
"$WINE_BIN" --version 2>/dev/null | sed 's/^/    /' || true

# --- Initialize the bottle ---------------------------------------------------
mkdir -p "$BOTTLES_DIR"
if [[ -d "$BOTTLE/drive_c" ]]; then
  ok "Bottle already initialized: $BOTTLE"
else
  log "Initializing bottle: $BOTTLE"
  # wineboot creates and initializes the prefix. Runs under Rosetta via wine_run.
  wine_run wineboot --init || die "wineboot failed."
  # Wait for the wineserver to settle before we call it done.
  WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -w 2>/dev/null || true
  ok "Bottle initialized"
fi

echo
ok "Step 1 complete."
echo "    Bottle (WINEPREFIX): $BOTTLE"
echo "    C: drive:            $BOTTLE/drive_c"
echo "    Next: scripts/02-graphics-stack.sh  (install DXVK/VKD3D + MoltenVK)"
