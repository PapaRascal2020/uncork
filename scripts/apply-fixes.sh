#!/usr/bin/env bash
# apply-fixes.sh: apply EVERY compat-DB fix for ONE game, on demand. This is
# what the app's "Apply fixes" button (shown when a game won't launch) calls.
# It's autoconfigure scoped to a single AppID, so a repair is fast and targeted:
#   - strip leftover wined3d/DXVK d3d*/dxgi from system32+syswow64 (keep
#     winemetal.dll) so 'native' overrides fall through to the DXMT builtin
#   - ensure the winemetal bridge PE is in system32
#   - strip d3d*/dxgi/winemetal from the game folder (don't shadow the builtin)
#   - drop steam_appid.txt
#   - install any required runtimes (winetricks verbs, e.g. dotnet40), ngen-safe
#
# Usage:  ./scripts/apply-fixes.sh <steam-appid>

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"
require_wine
appid="${1:?usage: apply-fixes.sh <steam-appid>}"

ENGINE_WIN="$WINE_HOME/lib/wine/x86_64-windows"
SYS="$BOTTLE/drive_c/windows/system32"; SYSW="$BOTTLE/drive_c/windows/syswow64"

manifest="$STEAMAPPS/appmanifest_${appid}.acf"
[[ -f "$manifest" ]] || die "No appmanifest for AppID $appid - is the game installed?"
installdir="$(sed -n 's/.*"installdir"[[:space:]]*"\(.*\)".*/\1/p' "$manifest" | head -1)"
GAME_DIR="$STEAMAPPS/common/$installdir"
log "Applying fixes for $installdir (AppID $appid)"

# 1) global: strip leftover d3d dlls from system32/syswow64; keep the bridge
n=0
for d in d3d11 d3d10core d3d10 d3d10_1 dxgi d3d9 d3d8; do
  for dir in "$SYS" "$SYSW"; do [[ -f "$dir/$d.dll" ]] && rm -f "$dir/$d.dll" && n=$((n+1)); done
done
cp -f "$ENGINE_WIN/winemetal.dll" "$SYS/winemetal.dll" 2>/dev/null || true
ok "Cleaned $n leftover system DLL(s); DXMT builtin will be used."

# 2) strip shadowing dlls from the game folder + set appid
if [[ -d "$GAME_DIR" ]]; then
  while IFS= read -r dll; do rm -f "$dll"; done < <(
    find "$GAME_DIR" -maxdepth 3 -type f \( -iname 'd3d11.dll' -o -iname 'd3d10core.dll' -o -iname 'dxgi.dll' \
      -o -iname 'd3d9.dll' -o -iname 'd3d8.dll' -o -iname 'winemetal.dll' \) 2>/dev/null)
  printf '%s\n' "$appid" > "$GAME_DIR/steam_appid.txt"
  ok "Game folder cleaned + appid set."
fi

# 3) install required runtimes (idempotent via winetricks.log)
runtimes="$(compat_get_list "$appid" winetricks | tr '\n' ' ')"
if [[ -n "${runtimes// }" ]]; then
  need=""
  for v in $runtimes; do grep -qx "$v" "$BOTTLE/winetricks.log" 2>/dev/null || need="$need $v"; done
  if [[ -n "${need// }" ]]; then
    log "Installing runtimes:$need (ngen-safe; can take a few minutes)…"
    "$(dirname "${BASH_SOURCE[0]}")/install-runtime.sh" $need || warn "runtime install had issues"
  else ok "Required runtimes already installed ($runtimes)."; fi
fi

echo
ok "Fixes applied for $installdir. Try launching again."
