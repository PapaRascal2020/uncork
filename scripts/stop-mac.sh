#!/usr/bin/env bash
# stop-mac.sh - quit a native macOS game. Scoped by the game's FULL install path
# (a unique, specific string, NOT a short human name), so it only ever matches
# that app's own processes. Never a bottle-wide or system-wide kill: there is no
# Wine prefix involved for a native app.
set -euo pipefail
APP="${1:?usage: stop-mac.sh <app-or-binary-path>}"
# pkill -f matches the full command line; the absolute .app path is specific to
# this game (e.g. /Users/x/Games/Foo.app/Contents/MacOS/Foo).
pkill -f "$APP" 2>/dev/null || true
exit 0
