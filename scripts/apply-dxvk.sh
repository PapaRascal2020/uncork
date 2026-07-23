#!/usr/bin/env bash
# apply-dxvk.sh: auto-wire DXVK for one installed game. This is the primitive
# the app runs automatically on game install/first-launch, so the USER never
# does it. It:
#   - locates the game's folder under steamapps/common
#   - finds its real D3D executables (skips crash handlers / redist installers)
#   - for each, drops the correctly-sized DXVK DLLs next to it and sets a
#     PER-APPLICATION Wine override (never bottle-wide, which breaks Steam)
#
# Usage:  ./scripts/apply-dxvk.sh "<game folder name substring>"
#   e.g.  ./scripts/apply-dxvk.sh "Styx"

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_wine
query="${1:?usage: apply-dxvk.sh <game folder name substring>}"

GAME_DIR="$(find "$STEAMAPPS/common" -maxdepth 1 -type d -iname "*${query}*" 2>/dev/null | head -1)"
[[ -d "$GAME_DIR" ]] || die "No installed game matching '*${query}*' under $STEAMAPPS/common"
log "Game: ${GAME_DIR##*/common/}"

# Candidate executables: the real game binaries, not tooling.
exes=()
while IFS= read -r e; do exes+=("$e"); done < <(
  find "$GAME_DIR" -iname '*.exe' 2>/dev/null \
    | grep -viE 'crashhandler|crashpad|vcredist|dxsetup|prereq|redist|[_-]?setup|installer|epicgames|unins|dotnet|directx'
)
[[ ${#exes[@]} -gt 0 ]] || die "No game executables found under $GAME_DIR"

applied=0
for exe in "${exes[@]}"; do
  dir="$(dirname "$exe")"
  base="$(basename "$exe")"
  # Detect PE bitness so we install matching DXVK DLLs (PE32+ = 64-bit).
  case "$(file -b "$exe" 2>/dev/null)" in
    *PE32+*) arch=x64 ;;
    *PE32*)  arch=x32 ;;
    *)       arch=x64 ;;
  esac
  apply_dxvk_to_game "$dir" "$base" "$arch"
  printf '    %-40s [%s]\n' "$base" "$arch"
  applied=$((applied+1))
done

WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -w 2>/dev/null || true
ok "DXVK wired for $applied executable(s)."
echo "    (App will do this automatically on install; run per game otherwise.)"
