#!/usr/bin/env bash
# install-runtime.sh: install a winetricks runtime verb (e.g. dotnet40) into the
# bottle AUTOMATICALLY and safely. This is the app-side equivalent of a Proton
# protonfix runtime step, macified, with one gotcha:
#
#   .NET installs spin forever in ngen/mscorsvw on Wine. The runtime FILES land
#   fine, but the optional native-image precompile never finishes and pegs a CPU
#   at 100%. So we watchdog mscorsvw and kill it once it's clearly stuck, then
#   reset the Windows version back to win10 (winetricks knocks it down to XP/7).
#
# Usage:  ./scripts/install-runtime.sh <winetricks-verb> [more verbs...]
#   e.g.  ./scripts/install-runtime.sh dotnet40
#
# winetricks is expected bundled (tools/) or on PATH / in Homebrew; the shipped
# app will bundle winetricks + cabextract so users never install anything.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_wine
[[ $# -ge 1 ]] || die "usage: install-runtime.sh <winetricks-verb> [more...]"

# Serialize runtime installs PER BOTTLE: two winetricks .NET installs into the
# same prefix at once corrupt each other. mkdir is atomic; the lock records our
# pid so a lock left by a force-killed installer is detected as stale + reclaimed
# (bottle_locked does that), rather than blocking every future install forever.
LOCK="$BOTTLE/.uncork-runtime.lock"
if bottle_locked; then
  die "A runtime install is already in progress for bottle '$BOTTLE_NAME'. Wait for it to finish."
fi
mkdir -p "$LOCK" 2>/dev/null || die "Couldn't acquire runtime lock for '$BOTTLE_NAME'."
echo "$$" > "$LOCK/pid"

# Always leave the bottle USABLE, even if we're killed mid-install. winetricks
# knocks the Windows version down to XP/7 for .NET verbs; if that isn't reverted,
# Steam refuses to start ("no longer supported on your operating system version").
# So on ANY exit (success, error, or SIGTERM/INT) kill stuck ngen, restore
# win10, and release the lock. Without this, a killed dotnet40 install can leave
# the Steam bottle unusable.
cleanup() {
  pkill -9 -f 'mscorsvw.exe' 2>/dev/null || true
  pkill -9 -f 'ngen.exe' 2>/dev/null || true
  /usr/bin/arch -x86_64 "$WINE_BIN" winecfg -v win10 >/dev/null 2>&1 || true
  rm -rf "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- locate winetricks + cabextract -----------------------------------------
find_bin() { for c in "$PROJECT_ROOT/tools/$1" "/opt/homebrew/bin/$1" "/usr/local/bin/$1" "$(command -v "$1" 2>/dev/null)"; do [[ -x "$c" ]] && { echo "$c"; return; }; done; }
WINETRICKS="$(find_bin winetricks)"; CABEXTRACT="$(find_bin cabextract)"
[[ -n "$WINETRICKS" ]] || die "winetricks not found (bundle it in tools/ or install via Homebrew)."
[[ -n "$CABEXTRACT" ]] || warn "cabextract not found - .NET verbs will fail to unpack. Bundle it in tools/."
export PATH="$(dirname "$WINETRICKS"):$(dirname "${CABEXTRACT:-$WINETRICKS}"):$PATH"

export WINE="$WINE_BIN" WINESERVER="$WINE_HOME/bin/wineserver" WINEPREFIX="$BOTTLE"
export WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=1 W_OPT_UNATTENDED=1

# --- ngen watchdog --------------------------------------------------------
# The .NET installer's ngen optimizer (mscorsvw) frequently WEDGES on Wine and
# never exits, so winetricks' "wait for processes" step hangs forever. It can
# wedge either SPINNING (100% CPU) or IDLE (~0% CPU), so judge it by PROGRESS
# (native images written), not CPU, and kill it once it's clearly not advancing.
# ngen is only an optimization; .NET works fine without it (JITs at runtime).
ngen_watchdog() {
  local stalled=0
  while :; do
    sleep 20
    pgrep -f 'winetricks' >/dev/null 2>&1 || return 0    # install finished
    pgrep -f 'mscorsvw.exe' >/dev/null 2>&1 || { stalled=0; continue; }
    local wrote
    wrote=$(find "$BOTTLE/drive_c/windows/Microsoft.NET" -name '*.dll' -newermt '-25 seconds' 2>/dev/null | grep -c .)
    if [[ "$wrote" -eq 0 ]]; then
      stalled=$((stalled+1))               # mscorsvw alive but no new native images
      if [[ "$stalled" -ge 3 ]]; then      # ~60s of no progress (spinning OR idle) = wedged
        warn "ngen/mscorsvw not progressing - killing it so the install can finish (optimization only)."
        pkill -9 -f 'mscorsvw.exe' 2>/dev/null; pkill -9 -f 'ngen.exe' 2>/dev/null
        stalled=0
      fi
    else stalled=0; fi                     # still writing images -> genuinely working
  done
}

for verb in "$@"; do
  log "Installing runtime '$verb' into bottle '$BOTTLE_NAME' (auto, ngen-safe)…"
  ngen_watchdog & WD=$!
  /usr/bin/arch -x86_64 "$WINETRICKS" -q "$verb" || warn "winetricks '$verb' returned non-zero (often OK if files landed)."
  kill "$WD" 2>/dev/null || true
  pkill -9 -f 'mscorsvw.exe' 2>/dev/null; pkill -9 -f 'ngen.exe' 2>/dev/null
done

# win10 restore + lock release happen in cleanup() (trap) so they run even if
# this install is interrupted; see the top of the script.
ok "Runtime install complete: $*"
