#!/usr/bin/env bash
# stop.sh - Stop a running game WITHOUT touching anything else.
#
# Two safety-critical rules (a system-wide `pkill -f` on a bare game name can take
# down unrelated processes like a browser or terminal):
#
#   1) NEVER match a short human string (folder name / title) against system
#      processes. Only ever match an absolute, bottle-scoped path that is unique
#      to one game: such a path appears in that game's own Wine processes and
#      nowhere else (not Steam, and certainly no native macOS app).
#   2) When we can identify the game's files precisely, kill ONLY those, so the
#      shared Steam client and any other running game keep going.
#
# Strategy by store:
#   - Steam: the shared "steam" bottle also hosts the hidden Steam client we want
#     to KEEP alive. Target only processes whose command line contains the game's
#     absolute install directory. TERM first, then KILL any stragglers.
#   - Epic / custom: these run in their own bottle with no background client to
#     preserve, so `wineserver -k` on that prefix is the clean, complete stop.
#
# Env:  BOTTLE_NAME (default "steam"), SOURCE ("Steam"|"Epic"|"App"), LAUNCH_ID

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SOURCE="${SOURCE:-Steam}"
LAUNCH_ID="${LAUNCH_ID:-}"

if [[ ! -d "$BOTTLE/drive_c" ]]; then
  warn "No such bottle: '$BOTTLE_NAME' - nothing to stop."
  exit 0
fi

# --- Steam: precise, game-only stop (Steam + other games keep running) -------
if [[ "$SOURCE" == "Steam" && -n "$LAUNCH_ID" ]]; then
  manifest="$STEAMAPPS/appmanifest_${LAUNCH_ID}.acf"
  if [[ -f "$manifest" ]]; then
    installdir="$(sed -n 's/.*"installdir"[[:space:]]*"\(.*\)".*/\1/p' "$manifest" | head -1)"
    GAME_DIR="$STEAMAPPS/common/$installdir"
    if [[ -n "$installdir" && -d "$GAME_DIR" ]]; then
      # SAFE BY DESIGN: we match "steamapps<sep>common<sep><installdir>", which is
      # unique to THIS game's files: it appears only in the game's own Wine procs,
      # never in Steam's or a macOS app's argv. We must match BOTH path styles:
      #   - D3DMetal direct-launch: Unix path  .../steamapps/common/<dir>/...
      #   - Steam -applaunch:       Windows path C:\...\steamapps\common\<dir>\...
      # so "<sep>" is a regex "." (matches / or \). The installdir is regex-escaped
      # so spaces/punctuation in folder names can't break or widen the pattern.
      esc="$(printf '%s' "$installdir" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
      pat="steamapps.common.${esc}"
      log "Stopping '$installdir' only (Steam stays running)…"
      pkill -TERM -f -- "$pat" 2>/dev/null || true
      # Let it exit cleanly (~3s), then KILL anything still alive.
      for _ in 1 2 3 4 5 6; do pgrep -f -- "$pat" >/dev/null 2>&1 || break; sleep 0.5; done
      pkill -KILL -f -- "$pat" 2>/dev/null || true
      ok "Stopped '$installdir'."
      exit 0
    fi
  fi
  warn "Couldn't resolve game dir for AppID '$LAUNCH_ID' - falling back to bottle stop."
fi

# --- Epic / custom (isolated bottle) or fallback: stop the whole prefix ------
log "Stopping bottle '$BOTTLE_NAME' (wineserver -k)…"
WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true
ok "Stopped '$BOTTLE_NAME'."
