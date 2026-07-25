#!/usr/bin/env bash
# play.sh - Launch an installed Steam game the way that actually works on Apple
# Silicon: Steam runs hidden purely as the Steamworks provider, and we launch the
# game's EXE *directly* (never `-applaunch`). Graphics go through DXMT (Metal),
# which is installed as a builtin in the engine (see scripts/autoconfigure.sh).
#
# Why direct-launch instead of `-applaunch`:
#   - `-applaunch` fired before Steam finished logging in, so launches were
#     silently dropped ("Play pressed, says running, nothing happens").
#   - Steam also carried stale "running game" state across unclean exits.
# So we start Steam, WAIT for a real login, then run the exe ourselves with
# SteamAppId set, the same model the working Epic/Legendary path uses.
#
# Usage:  ./scripts/play.sh <steam-appid> [relative/exe/path]
#   The exe is auto-detected from the game folder if not given.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"   # D3DMetal launch helpers
require_wine

# Live launch status the app streams to the Play button (so a slow first-launch
# Steam sign-in shows progress instead of a silent, seemingly-stuck button).
status() { printf '@@STATUS@@ %s\n' "$*"; _glog "[status] $*"; }
status "Preparing to launch…"
appid="${1:?usage: play.sh <steam-appid> [relative/exe/path]}"
exe_arg="${2:-}"

STEAM_EXE="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"
STEAM_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam"
CONN_LOG="$STEAM_ROOT/logs/connection_log.txt"
[[ -f "$STEAM_EXE" ]] || die "Steam not installed in the bottle."

# Don't launch while a runtime install holds the bottle: it's mid-reconfigure
# (e.g. Windows version temporarily set to XP for a .NET install).
if bottle_locked; then
  die "Components are still installing for this bottle. Please wait for that to finish, then launch."
fi

# --- Resolve the game folder from the app manifest --------------------------
manifest="$STEAMAPPS/appmanifest_${appid}.acf"
[[ -f "$manifest" ]] || die "No appmanifest for AppID $appid - is the game installed?"
installdir="$(sed -n 's/.*"installdir"[[:space:]]*"\(.*\)".*/\1/p' "$manifest" | head -1)"
GAME_DIR="$STEAMAPPS/common/$installdir"
[[ -d "$GAME_DIR" ]] || die "Game folder not found: $GAME_DIR"
log "Game: $installdir (AppID $appid)"

# --- Pick the exe to launch -------------------------------------------------
db_exe="$(compat_get "$appid" launch_exe)"
if [[ -n "$exe_arg" ]]; then
  GAME_EXE="$GAME_DIR/$exe_arg"
elif [[ -n "$db_exe" ]]; then
  GAME_EXE="$GAME_DIR/$db_exe"   # per-game launch exe from the compat DB
else
  # Largest non-tooling exe. maxdepth 4 (NOT 2): many games nest the real exe
  # (ETS2 at bin/win_x64/…, UE4 at Game/Binaries/Win64/…) so a shallow search finds
  # nothing and the game silently never launches. Skip crash handlers/redists.
  # Trailing `|| true`: an empty result must NOT abort the script under
  # `set -euo pipefail` (grep returns non-zero on no match); we want the friendly
  # `die` below to run instead of a silent exit.
  GAME_EXE="$(
    find "$GAME_DIR" -maxdepth 4 -iname '*.exe' 2>/dev/null \
      | grep -viE 'crashhandler|crashpad|vcredist|dxsetup|prereq|redist|[_-]?setup|installer|unins|dotnet|directx|cleaner|ffmpeg|notification|touchup|activation' \
      | while IFS= read -r e; do printf '%s\t%s\n' "$(stat -f '%z' "$e" 2>/dev/null || echo 0)" "$e"; done \
      | sort -rn | head -1 | cut -f2-
    true
  )"
fi
[[ -f "$GAME_EXE" ]] || die "Could not find a game exe under $GAME_DIR (pass one explicitly as arg 2)."
log "Exe: ${GAME_EXE##*/common/}"

# --- Per-game Windows version -----------------------------------------------
# Wine reports this PER-EXECUTABLE (AppDefaults), so pinning e.g. win7 for one
# game never affects Steam or other games. Fixes "no longer supported on your
# operating system" checks. Only touch the registry when a version is specified.
winver="$(compat_winver "$appid")"
if [[ -n "$winver" ]]; then
  exe_base="$(basename "$GAME_EXE")"
  wine_run reg add "HKCU\\Software\\Wine\\AppDefaults\\${exe_base}" /v Version /d "$winver" /f >/dev/null 2>&1 || true
  log "Windows version for ${exe_base}: $winver"
fi

# --- Graphics backend -------------------------------------------------------
# Per-game backend from the compat DB. Default to D3DMetal (Game Porting Toolkit)
# when it's installed (the fast, complete DirectX→Metal path), else DXMT.
exe_base="$(basename "$GAME_EXE")"
# Effective backend honours the user's per-game compatibility PROFILE (Steam-style
# engine picker) via compat_backend: selected profile -> its backend; else the
# game's DB backend; else auto (D3DMetal if GPTk present, else DXMT).
backend="$(compat_backend "$appid")"
[[ -n "$backend" ]] || backend="$(gptk_available && echo d3dmetal || echo dxmt)"
log "Compatibility profile: $(compat_profile "$appid" | sed 's/^$/auto/') → backend $backend"

# --- Steam DRM (SteamStub) detection ----------------------------------------
# A SteamStub-wrapped exe is encrypted and only decrypts with a signed-in Steam
# client that owns the app. It therefore CANNOT run through the isolated D3DMetal
# prefix (no Steam client lives there) and usually refuses a plain direct launch:
# it has to be started BY Steam (-applaunch), which decrypts it, then spawns it.
# Deciding this up front avoids the launch-die-retry flicker of trying D3DMetal
# and a direct launch first. The compat DB 'drm' field wins (true forces it, false
# disables it); otherwise auto-detect the SteamStub ".bind" PE section (the same
# marker Steamless uses). This is SteamStub-specific, so games that merely use the
# Steamworks API (most of them) are unaffected and keep their normal backend.
is_steam_stub() {  # <exe>  -> exit 0 if the PE carries a .bind (SteamStub) section
  py - "$1" <<'PY' 2>/dev/null
import sys, struct
try:
    f = open(sys.argv[1], "rb"); head = f.read(0x400)
    if head[:2] != b"MZ": sys.exit(1)
    pe = struct.unpack_from("<I", head, 0x3C)[0]
    f.seek(pe)
    if f.read(4) != b"PE\0\0": sys.exit(1)
    coff = f.read(20)
    nsec = struct.unpack_from("<H", coff, 2)[0]
    optsz = struct.unpack_from("<H", coff, 16)[0]
    f.seek(pe + 24 + optsz)          # section table = after PE sig + COFF + optional header
    for _ in range(nsec):
        if f.read(40)[:8].rstrip(b"\0") == b".bind": sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PY
}

game_log_init "Steam $installdir (appid $appid), exe ${GAME_EXE##*/}, backend $backend"

drm_flag="$(compat_get "$appid" drm)"
FORCE_APPLAUNCH=0
if [[ "$drm_flag" == "true" ]] || { [[ "$drm_flag" != "false" ]] && is_steam_stub "$GAME_EXE"; }; then
  log "Steam DRM detected (SteamStub / DB flag): launching through the Steam client."
  backend="dxmt"         # D3DMetal's isolated prefix has no Steam client; run in the main bottle
  FORCE_APPLAUNCH=1
fi

# Per-game DLL overrides fragment (user "dll_overrides"), appended to
# WINEDLLOVERRIDES in whichever launch path runs below.
dllo="$(compat_dll_overrides "$appid")"

# If the compat profile selects a specific GPTk engine VERSION, point the D3DMetal
# helpers at it and fetch it on demand (the Mac analog of picking a Proton version).
if [[ "$backend" == "d3dmetal" ]]; then
  eng="$(compat_engine_id "$appid")"
  if [[ -n "$eng" && "$eng" != "gptk" ]]; then
    gptk_use_engine "$eng"
    if ! gptk_available; then
      status "Downloading engine ($eng) - first use only…"
      log "Fetching GPTk engine '$eng' for the selected profile…"
      bash "$(dirname "${BASH_SOURCE[0]}")/ensure-profile.sh" "$(compat_profile "$appid")" \
        || warn "Engine '$eng' download failed."
    fi
    gptk_available || { warn "Engine '$eng' unavailable - using the default GPTk."; gptk_use_engine gptk; }
  fi
fi

# --- D3DMetal launch (bypasses the Steam client + -applaunch) ---------------
# Launch the game exe directly through GPTk Wine with D3DMetal, the way Whisky/
# vineport do. The Steam library is symlinked into the GPTk prefix so the game's
# C:\ paths and steam_api resolve. NOTE: SteamStub-DRM titles that require a live
# Steam client won't start this way; those fall back to the DXMT/-applaunch path
# by setting backend "dxmt" in the compat DB.
if [[ "$backend" == "d3dmetal" ]] && gptk_available; then
  status "Launching via D3DMetal…"
  log "Graphics backend: D3DMetal (Game Porting Toolkit) for $exe_base"
  ensure_gptk_prefix steam
  # Baseline game libraries (corefonts, d3dcompiler_47, vcrun2022) go into EVERY
  # D3DMetal prefix, not just the default engine that got them at store setup.
  # A downloaded engine version (e.g. gptk-2.1) has a fresh prefix, so provision
  # it here on first use. Idempotent (per-prefix marker → default engine skips
  # instantly); run in a subshell so winetricks' env doesn't leak into the launch.
  if [[ ! -f "$GPTK_PREFIX/.uncork-gptk-baseline" ]]; then
    status "Installing game libraries for this engine (first use)…"
    log "Provisioning baseline libraries into ${GPTK_PREFIX##*/}…"
    ( ensure_gptk_baseline steam ) >/dev/null 2>&1 || true
  fi
  gdc="$GPTK_PREFIX/drive_c/Program Files (x86)"
  if [[ ! -e "$gdc/Steam" ]]; then mkdir -p "$gdc"; ln -sfn "$STEAM_ROOT" "$gdc/Steam"; fi
  # DXMT bridge must not shadow D3DMetal in the game folder.
  for d in d3d11 dxgi d3d10core d3d9 d3d8 winemetal; do rm -f "$GAME_DIR/$d.dll"; done
  printf '%s\n' "$appid" > "$GAME_DIR/steam_appid.txt"
  ok "Launching $installdir via D3DMetal…"
  # Run the direct launch in a SUBSHELL (isolates GPTk env from the -applaunch
  # fallback below) and watch for the SteamStub-DRM instant-quit: if the exe dies
  # within ~12s, the game needs Steam to decrypt it, so fall through to the
  # DRM-safe `-applaunch` path instead of leaving the user with a Play button
  # that just flicked back. A genuinely-running game's process stays alive well
  # past 12s (even mid-load), so this won't false-trigger on slow first launches.
  (
    cd "$GAME_DIR"
    gptk_export_env
    [[ -n "$dllo" ]] && export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}$dllo"
    export SteamAppId="$appid" SteamGameId="$appid"
    exec "$GPTK_WINE" $(desktop_prefix) "$GAME_EXE" $(compat_launch_args "$appid") >>"$GAME_LOG" 2>&1
  ) &
  gpid=$!
  alive=1
  for _ in $(seq 1 12); do kill -0 "$gpid" 2>/dev/null || { alive=0; break; }; sleep 1; done
  if [[ "$alive" == "1" ]]; then
    log "Game running under D3DMetal."
    wait "$gpid"; exit 0
  fi
  status "Direct launch exited (likely Steam DRM) - retrying through Steam…"
  log "D3DMetal direct-launch exited <12s (SteamStub DRM?); falling back to -applaunch + DXMT."
  # fall through to the -applaunch path below (Steam client + DXMT graphics).
fi

# --- DXMT/DXVK prep (our Wine 11 + Steam client + -applaunch) ----------------
# DXMT = DirectX→Metal (engine builtin). DXVK = DirectX→Vulkan→Metal (MoltenVK).
if [[ "$backend" == "dxvk" ]]; then
  log "Graphics backend: DXVK (DirectX→Vulkan→Metal) for $exe_base"
  # Don't let the DXMT bridge shadow DXVK; install DXVK's DLLs into the game
  # folder + set per-exe 'native' overrides so ONLY this game uses DXVK.
  rm -f "$GAME_DIR/winemetal.dll"
  # Match DXVK arch to the GAME exe, not the host: a 32-bit game (PE32 i386, e.g.
  # older Unity titles) needs the x32 DXVK DLLs; x64 DLLs silently fail to load
  # and the game reports "no D3D9/D3D11" then dies. (NB: DXVK itself needs Vulkan
  # geometryShader, which MoltenVK lacks, so on Apple Silicon DXVK usually can't
  # get an adapter anyway; DXMT/D3DMetal are the working Metal backends.)
  dxvk_arch="x64"; file "$GAME_EXE" 2>/dev/null | grep -q "Intel 80386" && dxvk_arch="x32"
  log "DXVK arch: $dxvk_arch (game exe $(file "$GAME_EXE" 2>/dev/null | grep -oE 'Intel 80386|x86-64'))"
  apply_dxvk_to_game "$GAME_DIR" "$exe_base" "$dxvk_arch"
else
  log "Graphics backend: DXMT (DirectX→Metal) for $exe_base"
  # DXMT is the engine builtin: strip anything in the game folder that would
  # shadow it, and make sure the winemetal bridge PE is in system32.
  for d in d3d11 dxgi d3d10core d3d9 d3d8 winemetal; do rm -f "$GAME_DIR/$d.dll"; done
  ENGINE_WINEMETAL="$WINE_HOME/lib/wine/x86_64-windows/winemetal.dll"
  [[ -f "$ENGINE_WINEMETAL" ]] && cp -f "$ENGINE_WINEMETAL" "$BOTTLE/drive_c/windows/system32/winemetal.dll"
  # A PRIOR DXVK attempt (apply_dxvk_to_game) may have written per-exe 'native'
  # DllOverrides for the D3D DLLs into the registry. Those persist and force Wine
  # to load a native d3d11 that no longer exists → "could not load d3d11.dll
  # (80029c4a)", which defeats DXMT even after we install the builtin DLLs. The
  # WINEDLLOVERRIDES env below doesn't reliably beat a registry 'native' entry,
  # so DELETE them here; the DXMT path must own a clean slate. (User's explicit
  # advanced overrides ride WINEDLLOVERRIDES, not the registry, so this is safe.)
  for d in d3d8 d3d9 d3d10 d3d10core d3d11 dxgi; do
    wine_run reg delete "HKCU\\Software\\Wine\\AppDefaults\\${exe_base}\\DllOverrides" /v "$d" /f >/dev/null 2>&1 || true
  done
  # Force the DXMT D3D DLLs to load as BUILTIN. Without this, Wine's default
  # search can pick a stale/native d3d11 first, and a game (esp. 32-bit Unity
  # like Among Us) then reports "could not load d3d11.dll (80029c4a)" even though
  # the DXMT DLLs are installed and load fine on their own. Prepend so a user's
  # explicit per-game override (dllo) still wins if they set one.
  dllo="d3d11,dxgi,d3d10core=b${dllo:+;$dllo}"
fi
printf '%s\n' "$appid" > "$GAME_DIR/steam_appid.txt"

# --- Ensure Steam is up AND logged in ---------------------------------------
# Logged in IFF the most recent connection event is 'Logged On' (robust across
# log length: a plain tail-grep can scroll past the login line once Steam has
# been running a while, e.g. after pre-warm).
steam_logged_in() {
  local last
  last="$(grep -E 'Logged On|Logged Off' "$CONN_LOG" 2>/dev/null | tail -1)"
  [[ "$last" == *"Logged On"* ]]
}

# Bring Steam up through the shared, lock-serialized starter so a Play click can
# never race the app's pre-warm into a SECOND client (steamwebhelper conflict).
# If Steam is already up (pre-warmed) this returns immediately.
if ! steam_is_up; then status "Starting Steam…"; log "Starting Steam (hidden)…"; fi
steam_ensure_running || warn "Steam client did not come up; trying to launch anyway."

# ALWAYS wait for sign-in before launching, whether we just started Steam or it
# was pre-warmed. Firing -applaunch before 'Logged On' makes Steam silently DROP
# it (the game never starts and the button hangs on "Waiting for the game window").
# First sign-in in a fresh bottle (no cached credentials yet) genuinely takes a
# while under Wine, so tell the user up front rather than looking stuck. Marked
# once we've seen a successful login, so repeat launches show the short message.
FIRST_LOGIN_MARK="$BOTTLE/.uncork-steam-signed-in"
if ! steam_logged_in; then
  if [[ -f "$FIRST_LOGIN_MARK" ]]; then
    status "Signing in to Steam…"
  else
    status "Signing in to Steam (first time can take up to 2 minutes)…"
  fi
  for _ in $(seq 1 60); do steam_logged_in && break; sleep 3; done
fi
if steam_logged_in; then
  status "Steam ready"; ok "Steam is logged in."; touch "$FIRST_LOGIN_MARK" 2>/dev/null || true
else
  warn "Steam did not confirm login in time - launching anyway (may fail Steamworks init)."
fi

# --- Per-game tuning from the compat DB + user overrides --------------------
declare -a GAME_ENV=()
while IFS= read -r kv; do [[ -n "$kv" ]] && GAME_ENV+=("$kv"); done < <(compat_env "$appid")
if [[ "$(compat_hud_on "$appid")" == "1" ]]; then
  GAME_ENV+=("MTL_HUD_ENABLED=1"); log "Metal performance HUD: on"
fi
# User per-game DLL overrides ride along as WINEDLLOVERRIDES (advanced toggle).
[[ -n "$dllo" ]] && { GAME_ENV+=("WINEDLLOVERRIDES=$dllo"); log "DLL overrides: $dllo"; }
launch_args="$(compat_launch_args "$appid")"

# --- Launch the game --------------------------------------------------------
# Run the game EXE DIRECTLY, NOT `steam -applaunch`. When Steam is already
# running (our common case, since we start it above), a second
# `steam -applaunch <id> <args>` merely IPCs the running Steam, which then
# spawns the game from ITS OWN process, so our graphics env (WINEDLLOVERRIDES
# = builtin DXMT) and launch args (e.g. -force-d3d11-no-singlethreaded) never
# reach the game. The visible symptom: Unity's *multithreaded* D3D11 device
# creation spins forever on DXMT (100% CPU, stuck at "GfxDevice: creating
# device client", no window). Launching the exe ourselves puts the env + args
# on the actual game process. SteamStub DRM still decrypts: we wrote
# steam_appid.txt above and Steam is signed in. winemetal.so (the Metal
# unixlib) is located via DYLD_FALLBACK_LIBRARY_PATH.
GAME_ENV+=("DYLD_FALLBACK_LIBRARY_PATH=$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}")
GAME_ENV+=("SteamAppId=$appid" "SteamGameId=$appid" "SteamOverlayGameId=$appid")
game_exe_name="$(basename "$GAME_EXE")"

# Start the game THROUGH Steam so it decrypts SteamStub DRM then spawns the game.
# GAME_ENV (incl. the DXMT graphics overrides + the winemetal Metal-bridge search
# path) rides on the `wine steam.exe` process, and the game Steam spawns inherits
# it, so DXMT still applies even though we didn't run the exe ourselves.
# NB: ${arr[@]+"${arr[@]}"} expands to nothing when GAME_ENV is empty, the
# bash-3.2-safe idiom (plain "${GAME_ENV[@]}" throws "unbound variable" under -u).
applaunch_game() {
  env ${GAME_ENV[@]+"${GAME_ENV[@]}"} \
    WINEPREFIX="$BOTTLE" WINEDEBUG="${WINEDEBUG:--all}" MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}" \
    /usr/bin/arch -x86_64 "$WINE_BIN" "$STEAM_EXE" -applaunch "$appid" $launch_args >>"$GAME_LOG" 2>&1 &
}

if [[ "$FORCE_APPLAUNCH" == "1" ]]; then
  # Known Steam DRM: go straight through Steam (no doomed direct attempt first, so
  # the Play button doesn't flick running→stopped→running before the game starts).
  status "Launching ${installdir} through Steam… (the window can take up to 30 seconds)"
  log "Launching $installdir via Steam -applaunch $appid (DRM decrypt)."
  applaunch_game
  launched_via="applaunch"
else
  status "Launching ${installdir}… (the window can take up to 30 seconds)"
  log "Launching $installdir directly ($game_exe_name; DXMT graphics env on the game process)…"
  (
    cd "$GAME_DIR" 2>/dev/null || true
    env ${GAME_ENV[@]+"${GAME_ENV[@]}"} \
      WINEPREFIX="$BOTTLE" WINEDEBUG="${WINEDEBUG:--all}" MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}" \
      /usr/bin/arch -x86_64 "$WINE_BIN" $(desktop_prefix) "$GAME_EXE" $launch_args >>"$GAME_LOG" 2>&1
  ) &
  gpid=$!

  # DRM fallback for anything we didn't detect up front: if the direct process is
  # gone within ~14s AND no game process is running, retry through Steam.
  launched_via="direct"
  for _ in $(seq 1 7); do kill -0 "$gpid" 2>/dev/null || break; sleep 2; done
  if ! kill -0 "$gpid" 2>/dev/null && ! pgrep -f "$game_exe_name" >/dev/null 2>&1; then
    status "Direct launch exited early (Steam DRM?) - retrying through Steam…"
    log "Direct launch exited <14s; falling back to -applaunch $appid."
    applaunch_game
    launched_via="applaunch"
  fi
fi
ok "Launched $installdir (AppID $appid) via $launched_via."
echo "    The game window may take a few seconds to appear."
