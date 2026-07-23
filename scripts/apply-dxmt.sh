#!/usr/bin/env bash
# apply-dxmt.sh: wire DXMT (DirectX to Metal) for one installed game. This is the
# Metal-native runner for feature-level-11 games that DXVK can't back on Metal.
# Installs the winemetal unix bridge into the engine (once), drops DXMT's DLLs
# into the game folder, and sets per-application overrides.
#
# Usage:  ./scripts/apply-dxmt.sh "<game folder name substring>"

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_wine
query="${1:?usage: apply-dxmt.sh <game folder name substring>}"

[[ -f "$DXMT_BUILD/src/d3d11/d3d11.dll" ]] \
  || die "DXMT not built at $DXMT_BUILD (run the DXMT build first)."
[[ -f "$WINE_HOME/lib/wine/x86_64-unix/winemac.so" ]] || die "Wine engine missing."

GAME_DIR="$(find "$STEAMAPPS/common" -maxdepth 1 -type d -iname "*${query}*" 2>/dev/null | head -1)"
[[ -d "$GAME_DIR" ]] || die "No installed game matching '*${query}*'."
log "Game: ${GAME_DIR##*/common/}"

applied=0
while IFS= read -r exe; do
  # DXMT is 64-bit only here; skip 32-bit exes.
  case "$(file -b "$exe" 2>/dev/null)" in *PE32+*) ;; *) continue ;; esac
  apply_dxmt_to_game "$(dirname "$exe")" "$(basename "$exe")"
  printf '    %s  [DXMT]\n' "$(basename "$exe")"
  applied=$((applied+1))
done < <(find "$GAME_DIR" -iname '*.exe' 2>/dev/null \
           | grep -viE 'crashhandler|crashpad|vcredist|dxsetup|prereq|redist|[_-]?setup|installer|epicgames|unins|dotnet|directx|cleaner|ffmpeg')

WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -w 2>/dev/null || true
ok "DXMT wired for $applied executable(s)."
echo "    winemetal.so installed into the engine; per-game overrides set."
