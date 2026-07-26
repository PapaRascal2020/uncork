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

# Machine-aware client config (steam-profile.sh). "standard" (capable Macs) is the
# minimal known-good launch the M5 works on: `-cef-disable-gpu -noverifyfiles`.
# "low-resource" (<=8 GB Macs) adds the stability flags + -noreactlogin. Default is
# standard, so a capable machine can never get another machine's experimental flags.
source "$(dirname "${BASH_SOURCE[0]}")/steam-profile.sh"
steam_profile_config "$(steam_detect_profile)"

log "Launching Steam in bottle: $BOTTLE_NAME (profile: $STEAM_PROFILE)  ${*:+(args: $*)}"
if [[ "$*" == *"-shutdown"* ]]; then
  wine_run "$STEAM_EXE" "$@"
elif [[ -n "$STEAM_PROFILE_OVERRIDES" ]]; then
  WINEDLLOVERRIDES="$STEAM_PROFILE_OVERRIDES" wine_run "$STEAM_EXE" $STEAM_PROFILE_ARGS "$@"
else
  wine_run "$STEAM_EXE" $STEAM_PROFILE_ARGS "$@"
fi
