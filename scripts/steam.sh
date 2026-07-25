#!/usr/bin/env bash
# Helper: launch Steam (or run a Steam command) inside the MVP bottle.
#
#   ./scripts/steam.sh                 # launch the Steam client (log in here)
#   ./scripts/steam.sh -applaunch 865360   # launch a game by AppID
#   ./scripts/steam.sh -shutdown       # cleanly quit Steam in the bottle
#
# Runs in the foreground so you can see Steam's window and log in.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_wine

# Pre-warm: bring Steam up hidden through the shared, lock-serialized starter so
# it can never race a Play click into a second client. Best-effort and silent;
# the app calls this on open. Does nothing if Steam isn't installed yet.
if [[ "${1:-}" == "--prewarm" ]]; then
  steam_ensure_running || true
  exit 0
fi

STEAM_EXE="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"
[[ -f "$STEAM_EXE" ]] || die "Steam not installed in the bottle. Run scripts/03-install-steam.sh first."

# Before starting Steam (it's not running yet), stop background auto-updates so
# Steam doesn't hang on shutdown "Waiting for <game>…" (Wine + frequently-patched
# games like Among Us). No-op on a bare -shutdown, and it self-skips if Steam is up.
if [[ "$*" != *"-shutdown"* ]]; then
  STEAM_BOTTLE="$BOTTLE" bash "$(dirname "${BASH_SOURCE[0]}")/steam-tame.sh" >/dev/null 2>&1 || true
fi

# Once the update has FULLY completed (Steam writes package/*.installed at the very
# end), freeze further self-updates. Steam's post-update self-relaunch drops our
# -cef-disable-gpu, so the CEF login renders black and re-updating loops. Inhibiting
# once the client is COMPLETE stops that loop and boots straight to login with our
# flag, like a known-good bottle. We wait for the .installed marker (not just
# bin/cef): freezing mid-update leaves a half-installed client that also renders
# black. A fresh install runs its first update normally until the marker appears.
STEAM_ROOT="$(dirname "$STEAM_EXE")"
if [[ ! -f "$STEAM_ROOT/steam.cfg" ]] && \
   compgen -G "$STEAM_ROOT/package/steam_client_win*.installed" >/dev/null 2>&1; then
  printf 'BootStrapperInhibitAll=enable\nBootStrapperForceSelfUpdate=disable\n' > "$STEAM_ROOT/steam.cfg"
  log "Froze Steam self-update (client fully installed) to stop the CEF relaunch loop."
fi

log "Launching Steam in bottle: $BOTTLE_NAME  ${*:+(args: $*)}"
# `-cef-disable-gpu`: Steam's UI is CEF/Chromium; its GPU-accelerated compositor
# crashes intermittently under Wine (steamwebhelper → takes down steam.exe). Software
# CEF rendering is far more stable, the standard Steam-on-Wine fix. Not added for a
# bare `-shutdown` (no UI needed).
# WINEMSYNC=0: Steam's self-update downloader deadlocks under Wine's msync, so the
# client loops on "Updating Steam" (manifest downloads, packages never do). Disable
# msync/esync for the client; games use their own launch path and keep their sync.
# Stability recipe for the Steam client under Wine on Apple Silicon (from
# Steam-Win-Silicon), applied in full, not piecemeal:
#   -noverifyfiles     stop the bootstrapper reverting our CEF shim (also immutable)
#   -no-cef-sandbox    the CEF sandbox crashes under Wine
#   -forcedesktopscaling 1  avoid HiDPI scaling glitches
#   steamservice=d     disable steamservice.dll (flaky under Wine, can crash the client)
#   winemenubuilder.exe=d  don't hijack file associations / spawn menu builder
#   dcomp=n            DirectComposition native (CEF present path is steadier)
STEAM_OVERRIDES="steamservice=d;winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;dcomp=n"
if [[ "$*" == *"-shutdown"* ]]; then
  WINEMSYNC=0 WINEESYNC=0 wine_run "$STEAM_EXE" "$@"
else
  WINEMSYNC=0 WINEESYNC=0 WINEDLLOVERRIDES="$STEAM_OVERRIDES" \
    wine_run "$STEAM_EXE" -cef-disable-gpu -noverifyfiles -no-cef-sandbox -forcedesktopscaling 1 "$@"
fi
