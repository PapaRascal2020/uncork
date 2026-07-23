#!/usr/bin/env bash
# install-custom-store.sh: install a user-added WINDOWS store client into its own
# Wine bottle, then report the most likely launch .exe so Uncork can add a tile.
# (macOS custom stores need no install; they're a native .app shortcut.)
#
# Usage: install-custom-store.sh <bottle-name> <installer-path-on-host>
# Emits @@STEP@@ progress; on success prints a line:  FOUND_EXE=<unix path>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

BOTTLE_NAME="${1:?usage: install-custom-store.sh <bottle> <installer> [winver] [wait_for_exe]}"
INSTALLER="${2:?need installer path}"
WINVER="${3:-}"       # optional Windows version to set on the bottle (win10/win7/…)
WAIT_FOR="${4:-}"     # optional: proceed once this .exe appears (stall-proof, e.g. Battle.net)
PFX="$BOTTLES_DIR/$BOTTLE_NAME"
# NOTE: WINE_HOME already honours UNCORK_ENGINE (set by the caller) via lib.sh, so
# the installer runs on the chosen Wine version.
WINE="$WINE_HOME/bin/wine"; WINESERVER="$WINE_HOME/bin/wineserver"
export WINEPREFIX="$PFX" WINEDEBUG="${WINEDEBUG:--all}" WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=n;mshtml=}"
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

[[ -f "$INSTALLER" ]] || die "Installer not found: $INSTALLER"

step 10 "Preparing a bottle for this store…"
if [[ ! -e "$PFX/system.reg" ]]; then
  "$WINE" wineboot --init >/dev/null 2>&1 || true
  "$WINESERVER" -w 2>/dev/null || true
fi

if [[ -n "$WINVER" ]]; then
  step 30 "Setting Windows version ($WINVER)…"
  bash "$(dirname "${BASH_SOURCE[0]}")/apply-recipe.sh" "$BOTTLE_NAME" --winver "$WINVER" >/dev/null 2>&1 || true
fi

# Fresh agent state for a retry: stop any lingering (stalled) agent from a prior
# attempt in THIS bottle, then clear the half-updated Update Agent. Bottle-scoped
# kill only. Clearing ProgramData/Battle.net is the documented Battle.net reset.
if [[ -n "$WAIT_FOR" ]]; then
  "$WINESERVER" -k 2>/dev/null || true; sleep 1
  rm -rf "$PFX/drive_c/ProgramData/Battle.net" 2>/dev/null || true
fi

step 40 "Running the installer… (finish any installer prompts in its window)"
cp "$INSTALLER" "$PFX/drive_c/store-installer${INSTALLER##*.}" 2>/dev/null || true
"$WINE" "$INSTALLER" >/dev/null 2>&1 &
ip=$!; t=0
if [[ -n "$WAIT_FOR" ]]; then
  # Self-updating installer (Battle.net). Its Update Agent hangs at ~45% under Wine
  # because it needs WMI (which Wine stubs). Documented fix: kill the stuck Agent.exe
  # so the bootstrapper proceeds to install the client. `wine taskkill` is scoped to
  # THIS bottle (via WINEPREFIX); it never touches other bottles or macOS apps. Wait
  # up to 20 min for the real client to land in Program Files.
  while [[ "$t" -lt 1200 ]]; do
    if find "$PFX/drive_c/Program Files"* -iname "$WAIT_FOR" 2>/dev/null | grep -q .; then
      step 80 "Client installed."; break
    fi
    if [[ "$t" -ge 60 ]]; then "$WINE" taskkill /f /im Agent.exe >/dev/null 2>&1 || true; fi
    sleep 20; t=$((t+20))
  done
else
  while kill -0 "$ip" 2>/dev/null; do [[ "$t" -ge 600 ]] && break; sleep 4; t=$((t+4)); done
fi
# Bottle-scoped cleanup only. Never system-wide.
"$WINESERVER" -k 2>/dev/null || true; sleep 1
"$WINESERVER" -w 2>/dev/null || true

step 85 "Locating the store client…"
# Best-effort: the largest .exe under Program Files that isn't an installer/helper.
PF="$PFX/drive_c/Program Files"; PFX86="$PFX/drive_c/Program Files (x86)"
best="$(find "$PF" "$PFX86" -type f -iname '*.exe' 2>/dev/null \
        | grep -viE 'unins|setup|install|redist|vcredist|dxsetup|dotnet|crashreport|helper|update' \
        | while read -r f; do printf '%s\t%s\n' "$(stat -f%z "$f" 2>/dev/null || echo 0)" "$f"; done \
        | sort -rn | head -1 | cut -f2-)"

if [[ -n "$best" ]]; then
  step 100 "Store installed."
  ok "Installed custom store into bottle '$BOTTLE_NAME'."
  printf 'FOUND_EXE=%s\n' "$best"
else
  step 100 "Installer finished."
  warn "Couldn't auto-detect the store's .exe - you can point Uncork at it manually."
fi
