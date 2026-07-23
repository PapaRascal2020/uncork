#!/usr/bin/env bash
# Step 4: install (if needed) and launch the MVP game through Steam-in-bottle.
#
# Uses Steam's -applaunch, which installs the game first if it isn't present,
# then runs it. Steam must already be logged in (see scripts/steam.sh).
#
# Usage:
#   ./scripts/04-launch-game.sh              # uses STEAM_APPID (We Were Here Together)
#   STEAM_APPID=<id> ./scripts/04-launch-game.sh
#
# This is the moment the whole chain is validated end-to-end:
#   game (D3D11) → DXVK → Vulkan → MoltenVK → Metal, all x86 under Rosetta.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_wine
STEAM_EXE="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"
[[ -f "$STEAM_EXE" ]] || die "Steam not installed. Run scripts/03-install-steam.sh, then log in with scripts/steam.sh."

log "Launching AppID $STEAM_APPID via Steam"
warn "First run will download/install the game - this can take a while."
warn "If D3D fails to initialize, mainline DXVK likely needs the macOS fork:"
warn "  set DXVK_DIR to a Gcenx DXVK-macOS build and re-run scripts/02-graphics-stack.sh."
echo

# -applaunch installs-then-runs. Steam should already be running & logged in;
# if not, this also brings it up.
wine_run "$STEAM_EXE" -applaunch "$STEAM_APPID"

echo
ok "Launch command issued for AppID $STEAM_APPID."
echo "    Success = We Were Here Together reaches its main menu."
echo "    (Full co-op play needs a second player + second copy.)"
