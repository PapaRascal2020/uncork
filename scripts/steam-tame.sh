#!/usr/bin/env bash
# steam-tame.sh - stop Steam from doing BACKGROUND game updates, which under Wine
# make Steam hang on shutdown ("Waiting for <game>…"). Frequently-patched titles
# (e.g. Among Us) get an update queued by Steam's default "always keep updated"
# behaviour; on shutdown Steam waits for that update to pause/flush. Setting every
# game to "only update when I launch it" (AutoUpdateBehavior=1) removes the
# background activity, so the shutdown wait disappears. Also disables per-app
# autocloud in localconfig.vdf (best-effort) since Wine cloud sync can also stall.
#
# MUST run only when Steam is NOT running (Steam rewrites these files live).
# Usage: steam-tame.sh   (invoked by steam.sh before it starts Steam)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STEAM_BOTTLE="${STEAM_BOTTLE:-$BOTTLES_DIR/steam}"
STEAMAPPS="$STEAM_BOTTLE/drive_c/Program Files (x86)/Steam/steamapps"
[[ -d "$STEAMAPPS" ]] || exit 0   # nothing installed yet

# Bail if Steam is up; never edit its files underneath it.
if pgrep -f "Steam/steam.exe" >/dev/null 2>&1; then exit 0; fi

changed=0
for m in "$STEAMAPPS"/appmanifest_*.acf; do
  [[ -f "$m" ]] || continue
  # Set AutoUpdateBehavior to 1 (only update on launch). If the key exists with a
  # different value, rewrite it; if it's already 1, sed is a no-op.
  if grep -qaE '"AutoUpdateBehavior"[[:space:]]*"[^1]"' "$m"; then
    sed -i '' -E 's/("AutoUpdateBehavior"[[:space:]]*")[0-9]+"/\11"/' "$m" && changed=$((changed+1))
  fi
done

# Best-effort: turn OFF per-app autocloud in the user's localconfig.vdf so Steam
# doesn't try to sync cloud saves on shutdown (a common Wine stall). Only flips
# "autocloud" ... "enabled" style values; leaves structure intact.
LC="$(find "$STEAM_BOTTLE/drive_c/Program Files (x86)/Steam/userdata" -name localconfig.vdf 2>/dev/null | head -1)"
if [[ -n "$LC" && -f "$LC" ]]; then
  # autocloud blocks look like: "autocloud" { "last..." }; we instead set the
  # simpler global-ish app cloud flags. This is conservative: only rewrite an
  # explicit "cloudenabled" "1" if present.
  sed -i '' -E 's/("cloudenabled"[[:space:]]*")1"/\10"/g' "$LC" 2>/dev/null || true
fi

echo "@@STEP@@ 100 Steam tuned (no background updates)."
[[ "$changed" -gt 0 ]] && ok "Set $changed game(s) to update-on-launch (no background updates)." || true
exit 0
