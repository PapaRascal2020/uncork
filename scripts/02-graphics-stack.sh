#!/usr/bin/env bash
# Step 2: install the graphics translation stack into the bottle.
#
# DXVK (D3D9/10/11 → Vulkan) DLLs go into the prefix, and Wine is told to load
# them ("native") instead of its built-in D3D. MoltenVK (Vulkan → Metal) is
# already bundled in the Gcenx Wine build, so nothing to do there.
#
# VKD3D-Proton (D3D12) is intentionally NOT installed: the MVP game is D3D11.
#
# Usage:  ./scripts/02-graphics-stack.sh
# Idempotent: re-running re-copies the DLLs and re-asserts the overrides.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Preflight checks"
require_arm64
require_rosetta
require_wine
[[ -d "$BOTTLE/drive_c" ]] || die "Bottle not found. Run scripts/01-create-bottle.sh first."
[[ -d "$DXVK_DIR/x64" && -d "$DXVK_DIR/x32" ]] \
  || die "DXVK not found at $DXVK_DIR (need x64/ and x32/). See DXVK_DIR in lib.sh."
ok "Bottle + DXVK present"

# In a 64-bit WoW64 prefix: system32 holds 64-bit DLLs, syswow64 holds 32-bit.
SYS64="$BOTTLE/drive_c/windows/system32"
SYS32="$BOTTLE/drive_c/windows/syswow64"
[[ -d "$SYS64" && -d "$SYS32" ]] || die "Expected system32 + syswow64 in the bottle; is it a 64-bit prefix?"

# --- Install DXVK DLLs -------------------------------------------------------
log "Installing DXVK DLLs into the bottle"
for dll in "${DXVK_DLLS[@]}"; do
  src64="$DXVK_DIR/x64/${dll}.dll"
  src32="$DXVK_DIR/x32/${dll}.dll"
  [[ -f "$src64" ]] && cp -f "$src64" "$SYS64/${dll}.dll" && printf '    system32/%s.dll\n' "$dll"
  [[ -f "$src32" ]] && cp -f "$src32" "$SYS32/${dll}.dll" && printf '    syswow64/%s.dll\n' "$dll"
done
ok "DXVK DLLs copied"

# --- Tell Wine to prefer the native (DXVK) DLLs ------------------------------
# Registry override persists in the bottle: HKCU\Software\Wine\DllOverrides.
log "Setting DLL overrides to native"
for dll in "${DXVK_DLLS[@]}"; do
  wine_run reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$dll" /d native /f >/dev/null 2>&1 \
    && printf '    %s = native\n' "$dll"
done
WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -w 2>/dev/null || true
ok "Overrides set"

# --- Verify ------------------------------------------------------------------
log "Verifying"
missing=0
for dll in "${DXVK_DLLS[@]}"; do
  [[ -f "$SYS64/${dll}.dll" ]] || { warn "missing system32/${dll}.dll"; missing=1; }
done
overrides="$(wine_run reg query "HKCU\\Software\\Wine\\DllOverrides" 2>/dev/null | grep -Ec 'd3d|dxgi' || true)"
[[ "$missing" -eq 0 ]] && ok "All DXVK DLLs in place" || warn "Some DLLs missing (see above)"
ok "DllOverrides registered: $overrides entries"

echo
ok "Step 2 complete."
echo "    DXVK installed + overrides set. MoltenVK already bundled in Wine."
echo "    Note: mainline DXVK on MoltenVK is validated for real at game launch (Step 4)."
echo "          If D3D init fails there, set DXVK_DIR to a macOS fork and re-run this step."
echo "    Next: scripts/03-install-steam.sh  (install Steam into the bottle)"
