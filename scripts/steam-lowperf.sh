#!/usr/bin/env bash
# steam-lowperf.sh - capture the EXACT localconfig.vdf keys that Steam's low-resource
# settings write, so we can apply them safely later without guessing.
#
# WHY capture instead of hardcode: those settings (Low Performance Mode, Disable
# Community Content, Shader Pre-Caching off, ...) are absent from localconfig.vdf
# until you toggle them, their key names are undocumented and version-specific, and
# localconfig.vdf holds the sign-in. Writing keys we're unsure of could break login.
# So we learn the real keys from a machine where you've set them.
#
# Read-only except for making a timestamped backup copy. Flow (Steam logged in):
#   1) steam-lowperf.sh snapshot     # save current localconfig.vdf (the "before")
#   2) in the Steam client, toggle the low-resource settings, then QUIT Steam
#   3) steam-lowperf.sh diff         # print exactly which keys/values changed
# Give me the diff output and I'll build a defensive apply step from the real keys.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOTTLE="$BOTTLES_DIR/steam"
LC="$(find "$BOTTLE/drive_c/Program Files (x86)/Steam/userdata" -name localconfig.vdf 2>/dev/null | head -1)"
SNAP="${UNCORK_CACHE:-$UNCORK_DATA_DIR/cache}/localconfig.before.vdf"
mkdir -p "$(dirname "$SNAP")"

case "${1:-}" in
  snapshot)
    [[ -f "$LC" ]] || die "No localconfig.vdf yet (sign in to Steam once first)."
    cp "$LC" "$SNAP"
    ok "Saved a before-snapshot. Now toggle the settings in Steam, quit Steam, then: steam-lowperf.sh diff"
    ;;
  diff)
    [[ -f "$LC" ]] || die "No localconfig.vdf found."
    [[ -f "$SNAP" ]] || die "No snapshot to compare. Run: steam-lowperf.sh snapshot (before toggling)."
    echo "=== keys that changed after your toggles (these are the real setting keys) ==="
    diff <(sort "$SNAP") <(sort "$LC") | grep -E '^[<>]' | grep -viE 'timestamp|LastPlayed|avatar|cloud|rtime|token|secret|password' | head -60
    echo "=== (paste the above; that's the ground truth for a safe auto-apply) ==="
    ;;
  *)
    echo "usage: steam-lowperf.sh snapshot | diff"
    echo "  localconfig: ${LC:-<not found: sign in first>}"
    ;;
esac
