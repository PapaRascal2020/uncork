#!/usr/bin/env bash
# origin.sh - launch EA's legacy Origin client in Uncork.
#
# Why Origin (not the EA app): the modern EA app (EADesktop + EABackgroundService)
# hangs forever on its localhost gRPC IPC handshake under Wine. That is not a Wine
# bug: isolated reproducers show Wine's winsock/IOCP and every resolver path work,
# so the hang is internal to the gRPC compiled into EADesktop.exe and can't be fixed
# from outside (see wine-fixes/diagnostics/grpc-localhost/). Origin is EA's pre-2022
# monolithic client (one process, no background service, no localhost gRPC), the
# long-proven EA client on Wine/CrossOver/Proton, so Uncork targets Origin for the
# EA catalogue.
#
# Origin is a 32-bit Qt app with an old embedded browser (QtWebEngine, ~Chromium 60
# era) for its store/login, far older than the EA app's Chromium 135, so it does not
# hit the WoW64 crash that forces Ubisoft onto wine-cef. It runs on the bundled
# Wine 11 (wine-stable) by default; ENGINE is overridable as a compatibility option
# (wine-stable | wine-cef) that the app's per-launcher compat picker sets.
#
# Usage: origin.sh launch (default) | stop

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOTTLE_NAME="${ORIGIN_BOTTLE:-origin}"
PFX="$BOTTLES_DIR/$BOTTLE_NAME"

# Compatibility option: which Wine engine to run Origin on. Default = bundled Wine 11.
# Set ENGINE=wine-cef to fall back to the CrossOver CEF engine (only if Origin's
# embedded browser regresses on Wine 11, like Ubisoft's newer Chromium did).
ENGINE="${ORIGIN_ENGINE:-wine-stable}"
if [[ "$ENGINE" == "wine-cef" ]]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/ensure-wine-engine.sh" wine-cef >&2 || true  # download if slim build
fi
CEF_BUNDLE_PATH="$ENGINE_DIR/wine-cef/wswine.bundle"
[[ -x "$CEF_BUNDLE_PATH/bin/wine" ]] || CEF_BUNDLE_PATH="$UNCORK_DATA_DIR/engine/wine-cef/wswine.bundle"
if [[ "$ENGINE" == "wine-cef" && -x "$CEF_BUNDLE_PATH/bin/wine" ]]; then
  WINE_BUNDLE="$CEF_BUNDLE_PATH"
  WINE="$WINE_BUNDLE/bin/wine"; WINESERVER="$WINE_BUNDLE/bin/wineserver"
  export DYLD_FALLBACK_LIBRARY_PATH="$WINE_BUNDLE/lib:$WINE_BUNDLE/lib/wine:$WINE_HOME/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
else
  WINE="$WINE_HOME/bin/wine"; WINESERVER="$WINE_HOME/bin/wineserver"
  export DYLD_FALLBACK_LIBRARY_PATH="$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
fi

APPDIR="$PFX/drive_c/Program Files (x86)/Origin"
EXE="$APPDIR/Origin.exe"

export WINEPREFIX="$PFX"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
# Origin's IGO (in-game overlay) hooks are a common crash source under Wine and
# add nothing here; disable via EACore.ini (written at setup). No wine-mono needed.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=n;mshtml=}"
# Graphics: Origin's UI is light 2D; the compat backend (D3DMetal/DXMT) is chosen
# per-launcher and can be forced with WINEDLLOVERRIDES from the caller if needed.

RUNLOG="${UNCORK_CACHE:-${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/cache}/origin-runtime.log"
mkdir -p "$(dirname "$RUNLOG")" 2>/dev/null || true

stop_origin() {
  # Bottle-scoped only, never a system-wide pkill.
  for p in Origin.exe OriginWebHelperService OriginClientService QtWebEngineProcess IGOProxy EABackgroundService; do
    pkill -f "$p" 2>/dev/null || true
  done
  WINEPREFIX="$PFX" "$WINESERVER" -k 2>/dev/null || true
}

case "${1:-launch}" in
  stop) stop_origin; ok "Origin stopped."; exit 0 ;;
  launch) : ;;
  *) die "usage: origin.sh [launch|stop]" ;;
esac

[[ -f "$EXE" ]] || die "Origin isn't installed (no Origin.exe under $PFX). Run setup-origin.sh first."

log "Launching Origin (engine: $ENGINE)…"
cd "$APPDIR"
# Detached so Origin's window persists after this returns (like ea.sh). Origin's
# embedded browser uses --no-sandbox-equivalent Qt flags internally; no CEF flags
# needed. Runtime output captured for diagnostics.
nohup "$WINE" "$EXE" >"$RUNLOG" 2>&1 &
disown 2>/dev/null || true
ok "Origin launched - its window should appear shortly. (log: $RUNLOG)"
