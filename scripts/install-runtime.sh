#!/usr/bin/env bash
# install-runtime.sh: install a winetricks runtime verb (e.g. dotnet40) into the
# bottle AUTOMATICALLY and safely. This is the app-side equivalent of a Proton
# protonfix runtime step, macified, with one gotcha:
#
#   .NET installs spin forever in ngen/mscorsvw on Wine. The runtime FILES land
#   fine, but the optional native-image precompile never finishes and pegs a CPU
#   at 100%. ngen is only a startup optimization (.NET JITs without it), so we
#   reap mscorsvw/ngen the moment it appears rather than wait, then reset the
#   Windows version back to win10 (winetricks knocks it down to XP/7).
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

# --- ngen reaper ----------------------------------------------------------
# The .NET installer's ngen optimizer (mscorsvw) frequently WEDGES on Wine and
# never exits, so winetricks' "wait for processes" step hangs. ngen only
# PRE-compiles the framework's assemblies to native images: it's a startup
# optimization, and .NET works fine without it (it JITs at runtime). So we don't
# let it run at all: reap mscorsvw/ngen the moment it appears. Trade-off: the
# first .NET app launch JITs (marginally slower once), but the install never
# stalls on ngen. The framework FILES are installed by the MSI, not by ngen, so
# killing it doesn't harm the install.
ngen_reaper() {
  while :; do
    pgrep -f 'winetricks' >/dev/null 2>&1 || return 0    # install finished
    pkill -9 -f 'mscorsvw.exe' 2>/dev/null || true
    pkill -9 -f 'ngen.exe' 2>/dev/null || true
    sleep 2
  done
}

# --- download progress ------------------------------------------------------
# The .NET installers are big and winetricks downloads them SILENTLY, so the UI
# looked frozen for minutes. Watch the installer file grow in winetricks' cache
# against its known size and emit @@STEP@@ <pct> lines the app renders as a
# percentage. Known .NET downloads (name:approx-total-bytes); unknown verbs just
# get no bar (the static "downloading…" message stays).
DL_TABLE=(
  "ndp48-x86-x64-allos-enu.exe:121000000"
  "dotNetFx40_Full_x86_x64.exe:50000000"
)
dl_watch() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/winetricks"
  while :; do
    pgrep -f 'winetricks' >/dev/null 2>&1 || return 0    # install finished
    local pair name total f sz pct
    for pair in "${DL_TABLE[@]}"; do
      name="${pair%%:*}"; total="${pair##*:}"
      f="$(find "$cache" -type f -name "$name" 2>/dev/null | head -1)"
      [[ -f "$f" ]] || continue
      sz="$(stat -f %z "$f" 2>/dev/null || echo 0)"
      [[ "$sz" -gt 0 ]] || continue
      pct=$(( sz * 100 / total )); (( pct > 99 )) && pct=99
      if (( pct < 99 )); then printf '@@STEP@@ %s Downloading .NET…\n' "$pct"
      else printf '@@STEP@@ 99 Installing .NET (extracting)…\n'; fi
    done
    sleep 1
  done
}

for verb in "$@"; do
  log "Installing runtime '$verb' into bottle '$BOTTLE_NAME' (auto, ngen-safe)…"
  ngen_reaper & WD=$!
  dl_watch & DLW=$!
  /usr/bin/arch -x86_64 "$WINETRICKS" -q "$verb" || warn "winetricks '$verb' returned non-zero (often OK if files landed)."
  kill "$WD" "$DLW" 2>/dev/null || true
  pkill -9 -f 'mscorsvw.exe' 2>/dev/null; pkill -9 -f 'ngen.exe' 2>/dev/null
done

# win10 restore + lock release happen in cleanup() (trap) so they run even if
# this install is interrupted; see the top of the script.
ok "Runtime install complete: $*"
