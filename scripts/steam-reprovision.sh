#!/usr/bin/env bash
# steam-reprovision.sh - reproduce a brand-new user's first Steam run, to test the
# PUBLIC path end to end with NO hand-copying:
#   1. remove a downloaded (per-user) wine-stable engine so it is re-fetched AND
#      checksum-verified as ours (see verify_asset_sha),
#   2. wipe the Steam CLIENT in the steam bottle (keeps installed games in steamapps/
#      and logins in userdata/),
#   3. reinstall Steam from Valve's official installer + stage the client from Valve
#      (Option B) + freeze self-update.
# If this renders on a machine that ISN'T the dev Mac, that is real evidence the
# public path works for others. If it stays black, we have a genuine portability bug.
#
# DESTRUCTIVE. Guarded: refuses to run without UNCORK_REPROVISION_CONFIRM=1 so it can
# never wipe a working bottle by accident (e.g. the dev Mac's). Never a system kill.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

BOTTLE_NAME="steam"
BOTTLE="$BOTTLES_DIR/$BOTTLE_NAME"
STEAM_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam"

if [[ "${UNCORK_REPROVISION_CONFIRM:-0}" != "1" ]]; then
  echo "This will, for the Steam bottle only:"
  echo "  - remove a downloaded wine-stable engine so it re-fetches + checksum-verifies"
  echo "  - WIPE the Steam client at: $STEAM_ROOT"
  echo "    (keeps steamapps/ games and userdata/ logins)"
  echo "  - reinstall Steam from Valve + stage the client + freeze"
  echo
  echo "Re-run with UNCORK_REPROVISION_CONFIRM=1 to proceed. Do NOT run this on a Mac"
  echo "whose Steam bottle you want to keep."
  exit 0
fi

# Stop Steam in THIS bottle only (bottle-scoped, never system-wide).
step 5 "Stopping Steam…"
if [[ -x "$WINE_HOME/bin/wineserver" ]]; then
  WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true
  sleep 1
fi

# Force the engine to be re-fetched + verified as ours. Only touches a DOWNLOADED
# per-user engine; a bundled payload engine is already ours and read-only, leave it.
if [[ "$WINE_HOME" == "$UNCORK_DATA_DIR"/* && -d "$WINE_HOME" ]]; then
  step 15 "Removing the downloaded engine so it re-fetches (checksum-verified)…"
  rm -rf "$WINE_HOME"
fi

# Wipe the client but keep games + logins.
if [[ -d "$STEAM_ROOT" ]]; then
  step 25 "Wiping the Steam client (keeping games + logins)…"
  chflags -R nouchg "$STEAM_ROOT" 2>/dev/null || true   # clear our immutable CEF shim so rm works
  keepdir="$BOTTLE/.uncork-steam-keep"
  rm -rf "$keepdir"; mkdir -p "$keepdir"
  for k in steamapps userdata config; do
    [[ -e "$STEAM_ROOT/$k" ]] && mv "$STEAM_ROOT/$k" "$keepdir/" 2>/dev/null || true
  done
  rm -rf "$STEAM_ROOT"
  mkdir -p "$STEAM_ROOT"
  for k in steamapps userdata config; do
    [[ -e "$keepdir/$k" ]] && mv "$keepdir/$k" "$STEAM_ROOT/" 2>/dev/null || true
  done
  rmdir "$keepdir" 2>/dev/null || true
fi

# Reprovision via the PUBLIC path only: no local snapshot, so setup-steam installs
# from Valve + stages (Option B). (A machine under test, like the Air, has no
# snapshot on disk anyway.)
step 35 "Reprovisioning Steam from scratch (fetch engine, install from Valve, stage, freeze)…"
STEAM_CLIENT_SNAPSHOT="/nonexistent" STEAM_CLIENT_SNAPSHOT_URL="" \
  bash "$(dirname "${BASH_SOURCE[0]}")/setup-steam.sh"

step 100 "Reprovision complete."
ok "Steam reprovisioned via the public path. Open Steam to sign in; if the login renders, the public path works on this machine."
