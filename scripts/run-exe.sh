#!/usr/bin/env bash
# run-exe.sh - launch an arbitrary Windows .exe through Uncork's DXMT engine, for
# non-store games (GOG / itch / standalone). Graphics come from the engine's DXMT
# builtin, exactly like store games, with no Steam/Epic involved.
#
# The bottle is chosen by BOTTLE_NAME. Using a per-game name gives that game its
# OWN prefix (isolation) so its runtimes/tweaks can't disturb anything else; if
# the bottle doesn't exist yet it's created and made DXMT-ready automatically.
#
#   BOTTLE_NAME=custom-<id> ./scripts/run-exe.sh "/path/to/Game.exe" [<id>]
#
# <id> (optional) keys per-user overrides (e.g. the Metal HUD toggle).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"
require_wine
exe="${1:?usage: run-exe.sh <path-to-exe> [id]}"
ovid="${2:-}"
[[ -f "$exe" ]] || die "Executable not found: $exe"

# Don't launch while a runtime install is reconfiguring this bottle.
if bottle_locked; then
  die "Components are still installing for this bottle. Please wait, then launch."
fi

ensure_bottle   # create + DXMT-ready the (possibly per-game) prefix

# Per-game Metal HUD via user overrides (keyed by id), if provided.
declare -a GAME_ENV=()
if [[ -n "$ovid" && "$(compat_hud_on "$ovid")" == "1" ]]; then
  GAME_ENV+=("MTL_HUD_ENABLED=1"); log "Metal performance HUD: on"
fi

game_log_init "Custom ${exe##*/} in bottle '$BOTTLE_NAME' (DXMT/Metal)"
log "Launching ${exe##*/} in bottle '$BOTTLE_NAME' (DXMT/Metal)…"
cd "$(dirname "$exe")" 2>/dev/null || true   # so the game finds sibling DLLs
env ${GAME_ENV[@]+"${GAME_ENV[@]}"} \
  WINEPREFIX="$BOTTLE" WINEDEBUG="${WINEDEBUG:--all}" MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}" \
  /usr/bin/arch -x86_64 "$WINE_BIN" $(desktop_prefix) "$exe" >>"$GAME_LOG" 2>&1 &
ok "Launched ${exe##*/} (bottle: $BOTTLE_NAME)."
