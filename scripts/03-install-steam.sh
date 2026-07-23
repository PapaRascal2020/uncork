#!/usr/bin/env bash
# Step 3: install the Windows Steam client into the bottle.
#
# Downloads Valve's official SteamSetup.exe and runs it silently (/S). The first
# time you LAUNCH Steam it will self-update and ask you to log in; that part is
# interactive and is done via scripts/steam.sh (this step just installs it).
#
# Usage:  ./scripts/03-install-steam.sh
# Idempotent: skips the install if steam.exe already exists.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STEAM_SETUP_URL="${STEAM_SETUP_URL:-https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe}"
STEAM_EXE="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"

log "Preflight checks"
require_arm64; require_rosetta; require_wine
[[ -d "$BOTTLE/drive_c" ]] || die "Bottle not found. Run scripts/01-create-bottle.sh first."
ok "Bottle ready"

if [[ -f "$STEAM_EXE" ]]; then
  ok "Steam already installed: $STEAM_EXE"
else
  log "Downloading SteamSetup.exe"
  # Write to a WRITABLE cache, never the engine dir: in a shipped app the engine
  # lives in a read-only .app bundle. UNCORK_CACHE is set by the app; fall back to
  # a temp dir when run standalone from a dev checkout.
  cache="${UNCORK_CACHE:-${TMPDIR:-/tmp}/uncork-cache}"
  mkdir -p "$cache"
  setup="$cache/SteamSetup.exe"
  curl -L --fail --progress-bar "$STEAM_SETUP_URL" -o "$setup" || die "Download failed: $STEAM_SETUP_URL"

  log "Running Steam installer (silent)"
  # /S = NSIS silent install. Installs to C:\Program Files (x86)\Steam.
  # Note: the installer tries to auto-launch Steam at the end, which can throw a
  # page fault under Wine, harmless because the files are already extracted.
  wine_run "$setup" /S 2>&1 | grep -v 'page fault\|clipboard manager\|get_thread_times' || true
  WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true   # kill any crashed auto-launch
  rm -f "$setup"

  # Verify the real install footprint, not just steam.exe (the installer can
  # crash on auto-launch after a *complete* extraction, or during a partial one).
  STEAM_ROOT="$(dirname "$STEAM_EXE")"
  for need in "$STEAM_EXE" "$STEAM_ROOT/bin" "$STEAM_ROOT/public"; do
    [[ -e "$need" ]] || die "Incomplete Steam install - missing: ${need#"$BOTTLE/"}. Re-run, or try the installer without /S to watch the GUI."
  done
  ok "Steam installed (steam.exe + bin/ + public/ present)"
fi

echo
ok "Step 3 complete."
echo "    Steam client: $STEAM_EXE"
echo
echo "    NEXT (interactive - you drive these):"
echo "      1) Log in:        ./scripts/steam.sh"
echo "         Steam will self-update (downloads a few hundred MB) then show a login window."
echo "         Log in, let your library populate, then quit Steam."
echo "      2) Launch game:   ./scripts/04-launch-game.sh"
echo "         (installs + launches We Were Here Together, AppID $STEAM_APPID)"
