#!/usr/bin/env bash
# gptk.sh: shared Game Porting Toolkit (D3DMetal) helpers for Uncork.
# Source AFTER lib.sh. D3DMetal is Apple's DirectX->Metal translator (the fast,
# complete path, as used by Whisky/CrossOver). It rides on a GPTk-patched Wine
# (7.7) that is separate from our bundled Wine 11, so GPTk games get their own
# prefix (GPTk's older Wine would otherwise churn the Wine-11 prefix).
#
# Provides: gptk_available, ensure_gptk_prefix <store>, gptk_export_env,
#           gptk_wine (the wine64 binary path).

# The GPTk engine is DOWNLOADED on demand (not bundled), so it lives in a
# WRITABLE per-user dir, not the read-only app bundle.
GPTK_ROOT="${GPTK_ROOT:-${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/engine/gptk}"
GPTK_DIR="${GPTK_DIR:-$GPTK_ROOT/Game Porting Toolkit.app/Contents/Resources/wine}"
GPTK_WINE="$GPTK_DIR/bin/wine64"
GPTK_WINESERVER="$GPTK_DIR/bin/wineserver"
# Which engine id these paths point at (default "gptk"); set by gptk_use_engine.
GPTK_ENGINE_ID="${GPTK_ENGINE_ID:-gptk}"

# Point the GPTk helpers at a specific downloaded engine (compat profile). Lets a
# per-game profile use an alternate GPTk version (e.g. "gptk-2.1") living in its
# own writable engine dir, the Mac analog of choosing a different Proton version.
#   $1 = engine id (dir under <data>/engine, e.g. "gptk", "gptk-2.1")
gptk_use_engine() {
  GPTK_ENGINE_ID="${1:-gptk}"
  GPTK_ROOT="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/engine/${GPTK_ENGINE_ID}"
  GPTK_DIR="$GPTK_ROOT/Game Porting Toolkit.app/Contents/Resources/wine"
  GPTK_WINE="$GPTK_DIR/bin/wine64"
  GPTK_WINESERVER="$GPTK_DIR/bin/wineserver"
}

# True when the D3DMetal engine (GPTk Wine + D3DMetal.framework) is installed.
gptk_available() { [[ -x "$GPTK_WINE" && -d "$GPTK_DIR/lib/external/D3DMetal.framework" ]]; }

# Ensure a dedicated GPTk prefix for a store exists (created once). Sets GPTK_PREFIX.
#   $1 = store base name ("steam" / "epic") ; $2 = engine id (default the active one)
# Prefix is "<store>-<engine>", so an alternate GPTk version gets its OWN bottle
# (isolation: Wine versions never churn each other's prefix). Default engine
# "gptk" keeps the historical "<store>-gptk" name.
ensure_gptk_prefix() {
  local store="$1" engine="${2:-$GPTK_ENGINE_ID}"
  GPTK_PREFIX="$BOTTLES_DIR/${store}-${engine}"
  if [[ ! -e "$GPTK_PREFIX/system.reg" ]]; then
    log "Preparing D3DMetal prefix for '$store' ($engine, one-time)…"
    mkdir -p "$GPTK_PREFIX"
    WINEPREFIX="$GPTK_PREFIX" WINEDEBUG=-all "$GPTK_WINE" wineboot --init >/dev/null 2>&1 || true
    WINEPREFIX="$GPTK_PREFIX" "$GPTK_WINESERVER" -w 2>/dev/null || true
  fi
}

# Install the BASELINE runtime libraries into a store's D3DMetal prefix so most
# games run with no per-game config. Idempotent (marker),
# best-effort (a flaky verb logs + continues, never aborts setup),
# and only marks complete when EVERY verb installed cleanly (else retried next
# setup). Emits @@STEP@@ progress across ~70-95%. Verbs come from stores.json's
# gptk_baseline (fallback default), verified to install on GPTk Wine 7.7.
#   $1 = store base name (steam | epic | gog | ubisoft)
ensure_gptk_baseline() {
  local store="$1"
  gptk_available || { warn "D3DMetal engine missing - skipping baseline libraries."; return 0; }
  ensure_gptk_prefix "$store"                       # sets GPTK_PREFIX = <store>-gptk
  local marker="$GPTK_PREFIX/.uncork-gptk-baseline"
  [[ -f "$marker" ]] && { log "Game libraries already installed for '$store'."; return 0; }

  local wt cab
  wt="$(find_bin winetricks 2>/dev/null || true)"
  cab="$(find_bin cabextract 2>/dev/null || true)"
  [[ -n "$wt" ]] || { warn "winetricks not found - skipping baseline libraries."; return 0; }

  local verbs=()
  if command -v gptk_baseline_verbs >/dev/null 2>&1; then
    while IFS= read -r v; do [[ -n "$v" ]] && verbs+=("$v"); done < <(gptk_baseline_verbs)
  fi
  [[ ${#verbs[@]} -gt 0 ]] || verbs=(corefonts d3dcompiler_47 vcrun2022)

  # winetricks env, targeting the GPTk (D3DMetal) prefix. unset DYLD_LIBRARY_PATH
  # (D3DMetal loads via rpath; forcing it breaks the framework, see gptk_export_env).
  export WINE="$GPTK_WINE" WINESERVER="$GPTK_WINESERVER" WINEPREFIX="$GPTK_PREFIX"
  export WINEARCH=win64 WINEDEBUG="${WINEDEBUG:--all}" MVK_CONFIG_LOG_LEVEL=0
  export W_OPT_UNATTENDED=1 WINETRICKS_LATEST_VERSION_CHECK=disabled
  [[ -n "$cab" ]] && export PATH="$(dirname "$cab"):$PATH"
  unset DYLD_LIBRARY_PATH

  # winetricks records each finished verb (one per line) in the prefix's
  # winetricks.log, the source of truth for "installed", robust against a
  # spurious non-zero exit (e.g. GPTk Wine 7.7's "no longer supported" warning
  # made corefonts look failed even though it installed). We trust that log, not
  # the exit code, and SKIP verbs already recorded (so a retry is fast and a
  # harmless warning never causes an endless full re-install).
  local wt_log="$GPTK_PREFIX/winetricks.log"
  verb_installed() { grep -qxF "$1" "$wt_log" 2>/dev/null; }

  local n=${#verbs[@]} i=0 v pct
  for v in "${verbs[@]}"; do
    pct=$(( 70 + i * 25 / (n>0?n:1) )); i=$((i+1))
    if verb_installed "$v"; then log "  $v already installed - skipping"; continue; fi
    printf '@@STEP@@ %s %s\n' "$pct" "Installing game libraries ($v)…"
    log "Baseline: winetricks $v → ${GPTK_PREFIX##*/}"
    sh "$wt" -q "$v" >/dev/null 2>&1 || true    # exit code is unreliable; verify via the log below
    verb_installed "$v" && log "  $v ok" || warn "  '$v' didn't install - games needing it can add it per-game."
  done
  "$GPTK_WINESERVER" -w 2>/dev/null || true

  # Mark done when EVERY baseline verb is recorded installed (per winetricks.log).
  local all_done=1
  for v in "${verbs[@]}"; do verb_installed "$v" || all_done=0; done
  [[ "$all_done" == 1 ]] && { touch "$marker"; log "Baseline game libraries ready for '$store'."; } \
                         || warn "Some baseline libraries didn't install - will retry the missing ones next launch."
  return 0
}

# Export the D3DMetal launch environment. Requires ensure_gptk_prefix first.
# `=b` (builtin) forces Wine to use the D3DMetal DirectX DLLs (NOT native DXVK,
# which needs Vulkan the GPTk Wine doesn't provide). D3DM_* / ROSETTA_ADVERTISE_AVX
# are D3DMetal tunables from Apple's GPTk Read Me.
gptk_export_env() {
  export WINEPREFIX="$GPTK_PREFIX"
  export WINEARCH=win64
  export WINEMSYNC=1 WINEESYNC=1
  export WINEDEBUG="${WINEDEBUG:--all}"
  # CRITICAL: DYLD_LIBRARY_PATH must be UNSET. GPTk's Wine finds D3DMetal.framework
  # via its own rpath. Forcing DYLD_LIBRARY_PATH stops D3DMetal from loading, so
  # D3D11 device creation fails and Unity falls back to wined3d D3D9 (pink screen).
  unset DYLD_LIBRARY_PATH
  export WINEDLLOVERRIDES="d3d9,d3d10,d3d10core,d3d11,d3d12,d3d12core,dxgi=b"
  export D3DM_SUPPORT_DXR="${D3DM_SUPPORT_DXR:-1}"     # DXR on M3+ (safe on M5)
  export ROSETTA_ADVERTISE_AVX="${ROSETTA_ADVERTISE_AVX:-1}"
  export EOS_USE_ANTICHEATCLIENTNULL=1                 # EOS anti-cheat null client
}

gptk_wine() { printf '%s' "$GPTK_WINE"; }
