#!/usr/bin/env bash
# remove-store.sh - remove a game launcher completely so it can be set up fresh:
# stop it, delete its bottle(s) and login/state. Used by the "Remove" action.
# Env/arg: the store id (steam | epic | ea).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

store="${1:-${BOTTLE_NAME:-}}"
[[ -n "$store" ]] || die "usage: remove-store.sh <store>"

log "Removing '$store'…"

# Stop any Wine processes in this store's prefixes (bundled Wine + GPTk).
for pfx in "$BOTTLES_DIR/$store" "$BOTTLES_DIR/${store}-gptk"; do
  [[ -d "$pfx" ]] || continue
  WINEPREFIX="$pfx" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true
done
# GPTk wineserver too, if present.
GPTK_WS="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/engine/gptk/Game Porting Toolkit.app/Contents/Resources/wine/bin/wineserver"
for pfx in "$BOTTLES_DIR/${store}-gptk"; do
  [[ -d "$pfx" && -x "$GPTK_WS" ]] && WINEPREFIX="$pfx" "$GPTK_WS" -k 2>/dev/null || true
done
sleep 1

# Delete the bottles.
rm -rf "$BOTTLES_DIR/$store" "$BOTTLES_DIR/${store}-gptk"

# Epic: also clear the legendary login/config so it's a true fresh start.
if [[ "$store" == "epic" ]]; then
  rm -rf "${LEGENDARY_CONFIG_PATH:-${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/legendary}"
fi

ok "Removed '$store' - its bottle and data are gone. Set it up again anytime."
