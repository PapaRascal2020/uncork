#!/usr/bin/env bash
# One-time Steam login that BYPASSES Steam's (black, unrenderable) CEF login UI
# by using the client's command-line login. After one success, Steam caches a
# refresh token and every future launch logs in silently, so the black chrome
# never matters again.
#
# Security: the password is read with no echo (never shown, never stored in shell
# history). Run this yourself so no credentials pass through anything else.
#
# Usage:  ./scripts/steam-login.sh [username]
#         (you'll be prompted for anything not given)
#
# Steam Guard: if your account uses the mobile authenticator, you'll get a push
# to approve on your phone, just approve it. If it needs a typed code, enter it
# when prompted.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_wine
STEAM_EXE="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"
[[ -f "$STEAM_EXE" ]] || die "Steam not installed. Run scripts/03-install-steam.sh first."

# make sure no Steam is already running (else -login goes to the running instance)
WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true

user="${1:-}"
[[ -n "$user" ]] || read -r -p "Steam username: " user
read -r -s -p "Steam password: " pass; echo
[[ -n "$user" && -n "$pass" ]] || die "Username and password are both required."

log "Logging in as '$user' (approve the Steam Guard push on your phone if prompted)"
# Launch headless-ish: we drive login via CLI; the black UI may still appear but
# we don't need it. Login result is written to the Steam logs.
wine_run "$STEAM_EXE" -login "$user" "$pass" -silent >/dev/null 2>&1 &
unset pass

echo
ok "Login command issued."
echo "    Watch for a Steam Guard prompt on your phone and approve it."
echo "    Give it ~30-60s, then check login state with:"
echo "      grep -iE 'logon|login|Assigned|steamid' \\"
echo "        '$BOTTLE/drive_c/Program Files (x86)/Steam/logs/connection_log.txt' | tail"
