#!/usr/bin/env bash
# steam-cef-fix.sh - fix the black Steam login window by restarting the client with
# Uncork's CEF flag.
#
# After Steam self-updates, its bootstrapper relaunches steam.exe with its own
# default arguments, WITHOUT our `-cef-disable-gpu`, so the CEF/Chromium login
# window comes up on the GPU compositor and renders black. This stops Steam in its
# bottle (bottle-scoped, never a system-wide kill) and relaunches it through
# steam.sh, which reapplies `-cef-disable-gpu` (and WINEMSYNC=0), so the login
# window renders.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

BOTTLE_NAME="steam"
BOTTLE="$BOTTLES_DIR/$BOTTLE_NAME"
STEAM_EXE="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"

require_wine
[[ -f "$STEAM_EXE" ]] || die "Steam isn't installed yet, add Steam first."

step 25 "Stopping Steam…"
# Bottle-scoped ONLY. Never a system-wide kill.
WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true
sleep 1

step 65 "Relaunching Steam with the CEF fix…"
# Relaunch through steam.sh (applies -cef-disable-gpu + WINEMSYNC=0), detached so
# this script returns while Steam keeps running.
nohup bash "$(dirname "${BASH_SOURCE[0]}")/steam.sh" >/dev/null 2>&1 &
disown 2>/dev/null || true

step 100 "Done."
ok "Restarted Steam with the CEF fix, the login window should render now."
