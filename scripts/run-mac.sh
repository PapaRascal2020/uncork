#!/usr/bin/env bash
# run-mac.sh - launch a native macOS game (a .app bundle or a native binary)
# directly, with no Wine/engine. Used for Library items whose platform is Mac
# (user-added Mac games; later, native store builds). Emits @@STATUS@@ so Uncork's
# Play button shows live state; RunStore then tracks the running app via pgrep.
set -euo pipefail
APP="${1:?usage: run-mac.sh <app-or-binary-path> [launch-id]}"
status() { printf '@@STATUS@@ %s\n' "$1"; }

name="$(basename "$APP")"; name="${name%.app}"
[[ -e "$APP" ]] || { echo "Native game not found: $APP" >&2; exit 1; }
status "Launching ${name}…"

if [[ "$APP" == *.app ]]; then
  # Launch the bundle natively. `open` returns after handing off to the app;
  # RunStore's pgrep on the .app path then tracks running/quit.
  exec /usr/bin/open "$APP"
else
  chmod +x "$APP" 2>/dev/null || true
  exec "$APP"
fi
