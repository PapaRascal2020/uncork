#!/usr/bin/env bash
# autoconfigure.sh: the app's automatic per-library pass. Reads the
# protonfixes-for-Mac DB (compat/gamefixes.json) and applies every game's fix so
# the end user runs nothing. Modeled on Proton's protonfixes; macified.
#
# What it does, all data-driven from the DB:
#   GLOBAL (once):
#     - Strip leftover wined3d/DXVK d3d*/dxgi from system32+syswow64 (keep
#       winemetal.dll) so any 'native' override falls through to the DXMT builtin.
#     - Ensure the winemetal bridge PE is in system32.
#   PER GAME:
#     - Strip d3d*/dxgi/winemetal from the game folder (don't shadow the builtin).
#     - Install required winetricks runtimes (e.g. dotnet40) if missing (ngen-safe).
#     - Drop steam_appid.txt (direct-launch needs it).
#     - Report the DB verdict + launch exe.
#
# Usage:  ./scripts/autoconfigure.sh            (skips slow runtime installs; flags them)
#         ./scripts/autoconfigure.sh --install-runtimes   (also installs missing runtimes)

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"
require_wine
[[ -d "$STEAMAPPS/common" ]] || die "No Steam library found. Install Steam + a game first."

INSTALL_RUNTIMES=0; [[ "${1:-}" == "--install-runtimes" ]] && INSTALL_RUNTIMES=1

ENGINE_WIN="$WINE_HOME/lib/wine/x86_64-windows"
ENGINE_UNIX="$WINE_HOME/lib/wine/x86_64-unix"

# --- Preconditions: DXMT must be the engine builtin -------------------------
# (grep -c, not -q: grep -q SIGPIPEs strings and set -o pipefail then false-fails)
dxmt_builtin=$(strings -a "$ENGINE_WIN/d3d11.dll" 2>/dev/null | grep -ci 'winemetal.dll' || true)
[[ "${dxmt_builtin:-0}" -gt 0 ]] || die "DXMT is not the engine builtin. Install DXMT into $ENGINE_WIN first."
[[ -f "$ENGINE_UNIX/winemetal.so" ]] || die "Missing $ENGINE_UNIX/winemetal.so (DXMT unix bridge)."
ok "DXMT engine builtin present."

# --- GLOBAL cleanup ---------------------------------------------------------
SYS="$BOTTLE/drive_c/windows/system32"; SYSW="$BOTTLE/drive_c/windows/syswow64"
stripped_sys=0
for d in d3d11 d3d10core d3d10 d3d10_1 dxgi d3d9 d3d8; do
  for dir in "$SYS" "$SYSW"; do [[ -f "$dir/$d.dll" ]] && rm -f "$dir/$d.dll" && stripped_sys=$((stripped_sys+1)); done
done
cp -f "$ENGINE_WIN/winemetal.dll" "$SYS/winemetal.dll" 2>/dev/null || true
ok "Cleaned $stripped_sys leftover d3d dll(s) from system32/syswow64; winemetal bridge in place."

# --- runtime-installed check (idempotent) -----------------------------------
# Use winetricks' OWN record ($WINEPREFIX/winetricks.log), not just the presence
# of mscorlib.dll: a game's redist can leave a PARTIAL .NET (Client Profile,
# still on Wine-Mono) that would make us wrongly skip the real, Mono-removing
# winetricks install. winetricks.log lists each verb it actually completed.
runtime_done() { grep -qx "$1" "$BOTTLE/winetricks.log" 2>/dev/null; }
dotnet_installed() { runtime_done dotnet40 || runtime_done dotnet48; }

log "Scanning Steam library: $STEAMAPPS/common"
count=0; ready=0; needswork=0; runtime_todo=()
while IFS= read -r game_dir; do
  name="$(basename "$game_dir")"
  [[ "$name" == "Steamworks Shared" ]] && continue
  count=$((count+1))

  # appid from the manifest whose installdir matches this folder
  appid="$(grep -l "\"installdir\"[[:space:]]*\"$name\"" "$STEAMAPPS"/appmanifest_*.acf 2>/dev/null | head -1 | sed -n 's/.*appmanifest_\([0-9]*\)\.acf/\1/p')"

  verdict="$(compat_get "${appid:-0}" verdict)"; [[ -z "$verdict" ]] && verdict="$(compat_default verdict)"
  launch_exe="$(compat_get "${appid:-0}" launch_exe)"

  # strip shadowing dlls from the game folder
  stripped=0
  while IFS= read -r dll; do rm -f "$dll" && stripped=$((stripped+1)); done < <(
    find "$game_dir" -maxdepth 3 -type f \( -iname 'd3d11.dll' -o -iname 'd3d10core.dll' -o -iname 'dxgi.dll' \
      -o -iname 'd3d9.dll' -o -iname 'd3d8.dll' -o -iname 'winemetal.dll' \) 2>/dev/null)

  [[ -n "$appid" ]] && printf '%s\n' "$appid" > "$game_dir/steam_appid.txt"

  # runtimes required by this game
  runtimes="$(compat_get_list "${appid:-0}" winetricks | tr '\n' ' ')"
  runtime_state=""
  if [[ -n "${runtimes// }" ]]; then
    if [[ "$runtimes" == *dotnet* ]] && dotnet_installed; then runtime_state="(dotnet ✓)"
    elif [[ "$INSTALL_RUNTIMES" -eq 1 ]]; then
      log "  Installing runtimes for $name: $runtimes"
      "$(dirname "${BASH_SOURCE[0]}")/install-runtime.sh" $runtimes || warn "  runtime install issue for $name"
      runtime_state="(installed: $runtimes)"
    else runtime_state="NEEDS runtimes: $runtimes"; runtime_todo+=("$name: $runtimes"); fi
  fi

  case "$verdict" in works) ready=$((ready+1)); tag=works;; needs-work) needswork=$((needswork+1)); tag=needs-work;; *) tag="$verdict";; esac
  printf '  %-32s [%-10s appid=%-8s strip=%s] exe=%s %s\n' "${name:0:32}" "$tag" "${appid:-?}" "$stripped" "${launch_exe:-auto}" "$runtime_state"
done < <(find "$STEAMAPPS/common" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

echo
ok "Autoconfigure: $ready ready, $needswork need work, of $count game(s). Graphics = DXMT (engine builtin)."
if [[ ${#runtime_todo[@]} -gt 0 ]]; then
  warn "Runtimes to install (re-run with --install-runtimes, or the app installs in background):"
  for r in "${runtime_todo[@]}"; do echo "      $r"; done
fi
echo "    Launch any game with: scripts/play.sh <appid>"
