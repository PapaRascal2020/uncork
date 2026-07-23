#!/usr/bin/env bash
# ubisoft.sh - launch the Ubisoft Connect client (Uplay PC / CEF) in Uncork.
#
# Ubisoft Connect is a Chromium/CEF client (Chromium 135). Its renderer page-faults
# on our Wine 11 (a WoW64 bug that Steam's older Chromium 126 doesn't hit), so it
# runs on the CrossOver-patched Wine (engine/wine-cef) which avoids that crash.
#
# The blank/transparent-content bug is a graphics-path failure. Ubisoft Connect is
# 32-bit Chromium 135, and the needed D3D path is D3DMetal (D3D to Metal direct):
#   - wined3d/OpenGL throws GL_INVALID_FRAMEBUFFER_OPERATION on macOS 26 (legacy GL).
#   - DXVK is impossible: it needs Vulkan, MoltenVK is 64-bit only, this app is
#     32-bit so 32-bit DXVK can't init (crashes). No 32-bit Vulkan on Apple Silicon.
#   - So D3DMetal is the only working 32-bit path (what CrossOver ships).
# STATUS: this wine-cef bundle has winemetal.dll (bridge) but is missing the
# matched D3DMetal (winemetal.so + D3DMetal.framework + libmetalirconverter.dylib).
# Until those are added, the client launches (no crash) but content won't paint.
# ensure_ubisoft_gfx below stages what we have (MoltenVK) and is where the matched
# D3DMetal graft will go. Must launch from a GUI context (Uncork NSTask) to present.
#
# Usage: ubisoft.sh launch (default) | stop

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOTTLE_NAME="ubisoft-cef"
PFX="$BOTTLES_DIR/$BOTTLE_NAME"
# CrossOver 24 Wine (engine/wine-cef): Chromium 135's renderer page-faults on our
# Wine 11 (a WoW64 bug Steam's older Chromium 126 doesn't hit), but not on this
# CrossOver-patched Wine. Its dylib chain comes from our bundled wine-stable/lib.
# wine-cef may be bundled in the payload, or downloaded on demand (slim build).
bash "$(dirname "${BASH_SOURCE[0]}")/ensure-wine-engine.sh" wine-cef >&2 || true
CEF_BUNDLE="$ENGINE_DIR/wine-cef/wswine.bundle"
[[ -x "$CEF_BUNDLE/bin/wine" ]] || CEF_BUNDLE="$UNCORK_DATA_DIR/engine/wine-cef/wswine.bundle"
WINE="$CEF_BUNDLE/bin/wine"
WINESERVER="$CEF_BUNDLE/bin/wineserver"
APPDIR="$PFX/drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher"
EXE="$APPDIR/UbisoftConnect.exe"

export WINEPREFIX="$PFX"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
# Cross-process present (Uncork, experimental): force builtin DXMT for CEF's D3D11
# and enable the patched-winemac.drv consumer that displays DXMT's shared IOSurface
# in the window. Lets Ubisoft's CEF content actually paint.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d11,dxgi,d3d10core=b}"
export DXMT_CROSS_PROCESS_PRESENT="${DXMT_CROSS_PROCESS_PRESENT:-1}"
export DYLD_FALLBACK_LIBRARY_PATH="$CEF_BUNDLE/lib:$CEF_BUNDLE/lib/wine:$CEF_BUNDLE/lib/external:$WINE_HOME/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
# Cross-process present (Uncork, experimental): DXMT renders CEF's D3D11 into a
# shared IOSurface texture and patched winemac.drv displays it in the window.
# Force builtin DXMT and enable the winemac consumer poll. Runtime log tees to
# ubisoft-runtime.log for diagnostics.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d11,dxgi,d3d10core=b}"
export DXMT_CROSS_PROCESS_PRESENT="${DXMT_CROSS_PROCESS_PRESENT:-1}"
UBI_RUNLOG="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/cache/ubisoft-runtime.log"
mkdir -p "$(dirname "$UBI_RUNLOG")" 2>/dev/null || true
# Stage the graphics artifacts we have (idempotent). D3DMetal override goes here
# once the matched CrossOver-24 D3DMetal stack is bundled (see header).
ensure_ubisoft_gfx() {
  # MoltenVK reachable by this Wine's winevulkan/winemac.drv (fixes the winevulkan
  # load failure; also a prerequisite for any future Vulkan-backed path).
  if [[ ! -f "$CEF_BUNDLE/lib/libMoltenVK.dylib" && -f "$WINE_HOME/lib/libMoltenVK.dylib" ]]; then
    cp "$WINE_HOME/lib/libMoltenVK.dylib" "$CEF_BUNDLE/lib/libMoltenVK.dylib" 2>/dev/null || true
  fi
  # NOTE: DXVK deliberately NOT installed: this client is 32-bit and 32-bit DXVK
  # cannot initialise (no 32-bit Vulkan/MoltenVK on Apple Silicon); it crashes.
}

stop_ubi() {
  for p in UbisoftConnect upc.exe UplayWebCore UbisoftGameLauncher UplayService UbisoftExtension; do
    pkill -f "$p" 2>/dev/null || true
  done
  WINEPREFIX="$PFX" "$WINESERVER" -k 2>/dev/null || true
}

case "${1:-launch}" in
  stop) stop_ubi; ok "Ubisoft Connect stopped."; exit 0 ;;
  launch) : ;;
  *) die "usage: ubisoft.sh [launch|stop]" ;;
esac

[[ -f "$EXE" ]] || die "Ubisoft Connect isn't installed (no UbisoftConnect.exe under $PFX)."

ensure_ubisoft_gfx

log "Launching Ubisoft Connect…"
cd "$APPDIR"
# FOREGROUND (Uncork runs this via NSTask, staying alive) so CEF's child processes
# spawn and the window presents. Do NOT nohup/detach.
#   --no-sandbox                : Chromium's sandbox crashes the renderer under Wine.
#   --disable-direct-composition: Wine's DirectComposition is a stub; force Chromium
#       onto the DXGI-swapchain present path that Wine implements.
# GPU is left ENABLED so CEF's D3D11 reaches whatever D3D backend is installed. With
# D3DMetal grafted in, that becomes D3D11→Metal (the working 32-bit path). Until then
# it falls to wined3d/GL and content won't paint, but the client launches cleanly.
exec "$WINE" "$EXE" --no-sandbox --disable-direct-composition
