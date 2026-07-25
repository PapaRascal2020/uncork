#!/usr/bin/env bash
# steam-fix-updates.sh - repair a Steam bottle stuck on "Updating Steam".
#
# Steam's online self-update can fail under Wine (the client window opens, never
# downloads, then closes). This applies the known-good fixes, all scoped to the
# Steam bottle, never system-wide:
#   1. Stop any Steam running in THIS bottle (bottle-scoped wineserver -k).
#   2. If a local Steam client snapshot is on disk (a working, already-updated
#      client you copied in), restore it into the bottle so it has a complete
#      client and does not need the (failing) online update.
#   3. Write steam.cfg (BootStrapperInhibitAll) so Steam skips the self-update and
#      boots straight to the login window.
#
# We do NOT download a client from Uncork (we do not host Valve's client). This only
# reuses a snapshot you placed on disk yourself, plus the update-inhibit config. If
# no snapshot is present, a fresh install cannot be repaired offline: the client
# files themselves are what is missing, so copy a working snapshot in first (see the
# STEAM_CLIENT_SNAPSHOT note in setup-steam.sh).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

BOTTLE_NAME="steam"
BOTTLE="$BOTTLES_DIR/$BOTTLE_NAME"
STEAM_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_ROOT/steam.exe"
INSTALLED_MARKER="$STEAM_ROOT/package/steam_client_win64.installed"

# Where a local snapshot may live (per-user engine dir, or STEAM_CLIENT_SNAPSHOT).
SNAPSHOT_USER_DIR="$UNCORK_DATA_DIR/engine/steam-client-snapshot"
SNAPSHOT="${STEAM_CLIENT_SNAPSHOT:-$SNAPSHOT_USER_DIR}"
[[ -d "$SNAPSHOT/package" ]] || SNAPSHOT="$ENGINE_DIR/steam-client-snapshot"

require_wine
[[ -d "$BOTTLE/drive_c" ]] || die "No Steam bottle yet. Add Steam first, then apply this patch."

step 10 "Stopping Steam in the bottle…"
# Bottle-scoped ONLY. Never a system-wide kill.
WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true

restored=0
if [[ -d "$SNAPSHOT/package" ]]; then
  step 40 "Restoring the working Steam client…"
  mkdir -p "$STEAM_ROOT"
  ( cd "$SNAPSHOT" && for item in *; do
      cp -Rc "$item" "$STEAM_ROOT/" 2>/dev/null || cp -R "$item" "$STEAM_ROOT/"
    done )
  restored=1
fi

step 80 "Disabling the broken self-update…"
mkdir -p "$STEAM_ROOT"
printf 'BootStrapperInhibitAll=enable\nBootStrapperForceSelfUpdate=disable\n' > "$STEAM_ROOT/steam.cfg"

step 100 "Done."
if [[ "$restored" == 1 && -f "$STEAM_EXE" && -f "$INSTALLED_MARKER" ]]; then
  ok "Patched: restored a working Steam client and disabled the self-update. Sign in next."
elif [[ -f "$STEAM_EXE" ]]; then
  warn "Disabled the self-update, but this bottle has no complete client to restore."
  warn "Copy a working Steam client snapshot to: $SNAPSHOT_USER_DIR (so .../package/ exists), then apply again."
else
  die "No Steam client in the bottle and no local snapshot to restore. Add Steam, or place a snapshot at $SNAPSHOT_USER_DIR."
fi
