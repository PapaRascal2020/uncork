#!/usr/bin/env bash
# Shared configuration and helpers for the WineOnMac MVP pipeline.
# Source this from each numbered step script.

set -euo pipefail

# --- Paths -------------------------------------------------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="${ENGINE_DIR:-$PROJECT_ROOT/engine}"
BOTTLES_DIR="${BOTTLES_DIR:-$PROJECT_ROOT/bottles}"

# The Steam bottle: one Wine prefix hosting the Steam client + ALL its games
# (they install into C:\Program Files (x86)\Steam\steamapps\common inside it).
BOTTLE_NAME="${BOTTLE_NAME:-steam}"
BOTTLE="${BOTTLES_DIR}/${BOTTLE_NAME}"          # this is the WINEPREFIX

# --- Engine ------------------------------------------------------------------
# x86-64 Wine build that runs under Rosetta 2. Override WINE_URL to pin a build.
# Pinned: Gcenx macOS_Wine_builds wine-STABLE 11.0 (LGPL). IMPORTANT: use stable,
# NOT staging: on wine-staging 11.10 Steam's single-process CEF helper crash-loops
# on a winsock error (WSALookupServiceBegin); on stable 11.0 that error is
# non-fatal and Steam's login UI renders. See docs/DECISIONS.md.
# The asset is a `.tar.xz` containing a "Wine Stable.app" bundle; the wine tree
# lives at Contents/Resources/wine, which 01-create-bottle.sh extracts.
WINE_URL="${WINE_URL:-https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz}"
# Path INSIDE the archive to the wine tree, and how many leading components to strip.
WINE_ARCHIVE_SUBTREE="${WINE_ARCHIVE_SUBTREE:-Wine Stable.app/Contents/Resources/wine}"
WINE_ARCHIVE_STRIP="${WINE_ARCHIVE_STRIP:-4}"

# wine-cef: the CrossOver-based Wine for CEF launcher clients (Ubisoft/EA/Origin).
# When a slim build omits it from the payload, ensure-wine-engine.sh downloads it
# into the writable per-user engine dir. Host the tarball and point WINE_CEF_URL at
# it to enable that download.
WINE_CEF_URL="${WINE_CEF_URL:-https://github.com/PapaRascal2020/uncork/releases/download/wine-cef/wine-cef.tar.gz}"

# Our wine-stable engine has DXMT (DirectX->Metal) baked in: a ~20 MB d3d11.dll plus
# the winemetal.dll / winemetal.so Metal bridge. The PUBLIC Gcenx build (WINE_URL,
# above) ships only the tiny stock wined3d d3d11 and NO winemetal, so a slim build
# that fetched Gcenx cannot create a D3D11 device and every DirectX 11 game fails.
# Slim builds must therefore fetch OUR engine from this release asset, not Gcenx.
# Packaged (wine tree at the archive root) + uploaded by scripts/upload-assets.sh.
WINE_STABLE_ASSET_URL="${WINE_STABLE_ASSET_URL:-https://github.com/PapaRascal2020/uncork/releases/download/wine-stable/wine-stable.tar.gz}"

# Writable per-user data root (bottles + downloaded engines live here; the payload
# engine dir is read-only in a shipped .app).
UNCORK_DATA_DIR="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}"

# Python for the bundled Epic/GOG clients and our small JSON helpers. Uncork does
# NOT require the Xcode Command Line Tools: a relocatable Python is fetched on
# demand (ensure-python.sh), like the Wine engine. Resolution order: an explicit
# override, a bundled interpreter (payload), the fetched per-user one, then a
# system python3 if the user happens to have one.
_resolve_python() {
  local c
  for c in "${UNCORK_PYTHON:-}" \
           "$ENGINE_DIR/python/bin/python3" \
           "$UNCORK_DATA_DIR/engine/python/bin/python3" \
           "/usr/bin/python3"; do
    [[ -n "$c" && -x "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
UNCORK_PYTHON="$(_resolve_python || true)"

# Run Python without caring where it came from. Non-fatal callers (JSON helpers)
# use this; it falls back to a system python3 so a lookup never hard-fails here.
py() { "${UNCORK_PYTHON:-/usr/bin/python3}" "$@"; }

# Ensure a usable Python exists, fetching the relocatable build if needed. Sets
# UNCORK_PYTHON. Call this in first-run-capable paths before running the clients.
require_python() {
  UNCORK_PYTHON="$(_resolve_python || true)"
  [[ -n "$UNCORK_PYTHON" ]] && return 0
  bash "$PROJECT_ROOT/scripts/ensure-python.sh" >&2 || true
  UNCORK_PYTHON="$(_resolve_python || true)"
  [[ -n "$UNCORK_PYTHON" ]] || die "Python could not be provisioned. See scripts/ensure-python.sh."
}
# Prefer a bundled wine-stable (payload); if it's absent (a slim build), fall back
# to the per-user engine dir so 01-create-bottle.sh DOWNLOADS it there (from the
# public Gcenx WINE_URL) instead of failing to write into the read-only payload.
if [[ -x "$ENGINE_DIR/wine-stable/bin/wine" ]]; then
  WINE_HOME="${WINE_HOME:-$ENGINE_DIR/wine-stable}"  # extracted wine tree (bin/lib/share)
else
  WINE_HOME="${WINE_HOME:-$UNCORK_DATA_DIR/engine/wine-stable}"
fi

# --- Selectable Wine engine --------------------------------------------------
# UNCORK_ENGINE lets any caller (templates, custom stores, per-game compat) pick
# WHICH Wine runs the bottle. Resolves the engine id to its wine tree:
#   ""/wine-stable/default → bundled Wine 11 (+DXMT)
#   wine-cef               → CrossOver CEF bundle
#   wine-stable-11.0 | wine-staging-* | wine-devel-*  → downloaded Wine builds
#                            (Wine Manager → engine/wine-builds/<id>, writable data)
#   anything else present under engine/wine-builds/<id> or engine/<id>
if [[ -n "${UNCORK_ENGINE:-}" && "${UNCORK_ENGINE}" != "wine-stable" && "${UNCORK_ENGINE}" != "default" && "${UNCORK_ENGINE}" != "auto" ]]; then
  case "$UNCORK_ENGINE" in
    wine-cef)
      # per-user (downloaded, slim build) first, then bundled payload.
      for _c in "$UNCORK_DATA_DIR/engine/wine-cef/wswine.bundle" "$ENGINE_DIR/wine-cef/wswine.bundle"; do
        [[ -x "$_c/bin/wine" ]] && { WINE_HOME="$_c"; break; }
      done ;;
    *)
      if   [[ -x "$UNCORK_DATA_DIR/engine/wine-builds/$UNCORK_ENGINE/bin/wine" ]]; then WINE_HOME="$UNCORK_DATA_DIR/engine/wine-builds/$UNCORK_ENGINE"
      elif [[ -x "$ENGINE_DIR/wine-builds/$UNCORK_ENGINE/bin/wine" ]];             then WINE_HOME="$ENGINE_DIR/wine-builds/$UNCORK_ENGINE"
      elif [[ -x "$ENGINE_DIR/$UNCORK_ENGINE/bin/wine" ]];                          then WINE_HOME="$ENGINE_DIR/$UNCORK_ENGINE"
      fi ;;
  esac
fi
# Wine 11+ (new WoW64) ships a single `wine` binary, no separate wine64.
WINE_BIN="${WINE_BIN:-$WINE_HOME/bin/wine}"

# Locate a bundled/host tool (winetricks, cabextract, …). Prefers our bundled
# tools/, then Homebrew, then PATH. Shared so every script resolves tools the
# same way (setup, install-runtime, gptk baseline).
find_bin() { for c in "$PROJECT_ROOT/tools/$1" "/opt/homebrew/bin/$1" "/usr/local/bin/$1" "$(command -v "$1" 2>/dev/null)"; do [[ -x "$c" ]] && { echo "$c"; return; }; done; }

# DXVK (D3D9/10/11 → Vulkan). Extracted tree with x64/ and x32/ DLL dirs.
# Default is mainline DXVK; set DXVK_DIR to a macOS/MoltenVK fork (e.g. Gcenx
# DXVK-macOS) if mainline fails against MoltenVK. DLLs to install + override:
if [[ -d "$ENGINE_DIR/dxvk/x64" ]]; then DXVK_DIR="${DXVK_DIR:-$ENGINE_DIR/dxvk}"
else DXVK_DIR="${DXVK_DIR:-$UNCORK_DATA_DIR/engine/dxvk}"; fi   # per-user when not bundled (fetched on demand)
DXVK_DLLS=(dxgi d3d11 d3d10core d3d9 d3d8)

# VKD3D-Proton (D3D12 → Vulkan) is DEFERRED: not needed for D3D11 titles, and its
# release ships as .tar.zst which macOS bsdtar can't open without a `zstd` binary.

# DXMT (DirectX → Metal directly). The Metal-native runner for feature-level-11
# games that DXVK can't back on Metal. Built at thirdparty/dxmt/build (x86-64).
DXMT_BUILD="${DXMT_BUILD:-$PROJECT_ROOT/thirdparty/dxmt/build}"

# Apply DXMT to one game (64-bit). Installs the winemetal unix bridge into the
# Wine engine (once), drops DXMT's PE DLLs into the game folder, and sets
# per-application overrides so ONLY that exe uses DXMT.
apply_dxmt_to_game() {
  local game_dir="$1" exe="$2"
  # Metal bridge (wine unixlib): needs the -fvisibility Wine rebuild to work.
  cp -f "$DXMT_BUILD/src/winemetal/unix/winemetal.so" "$WINE_HOME/lib/wine/x86_64-unix/winemetal.so"
  # DXMT's D3D DLLs (locations within the meson build tree)
  cp -f "$DXMT_BUILD/src/d3d11/d3d11.dll"           "$game_dir/d3d11.dll"
  cp -f "$DXMT_BUILD/src/dxgi/dxgi.dll"             "$game_dir/dxgi.dll"
  cp -f "$DXMT_BUILD/src/d3d10/d3d10core.dll"       "$game_dir/d3d10core.dll"
  cp -f "$DXMT_BUILD/src/winemetal/winemetal.dll"   "$game_dir/winemetal.dll"
  for dll in dxgi d3d11 d3d10core winemetal; do
    wine_run reg add "HKCU\\Software\\Wine\\AppDefaults\\${exe}\\DllOverrides" \
      /v "$dll" /d native /f >/dev/null 2>&1
  done
}

# Target game
STEAM_APPID="${STEAM_APPID:-865360}"            # We Were Here Together (Unity, D3D11)
STEAMAPPS="$BOTTLE/drive_c/Program Files (x86)/Steam/steamapps"

# Apply DXVK to ONE game only. A PREFIX-WIDE DXVK override feeds DXVK into
# Steam's own 32-bit client and crashes it, so:
#   1) drop the DXVK DLLs into the game's own folder (app-dir load, not system32)
#   2) set a PER-APPLICATION override (HKCU\...\AppDefaults\<exe>\DllOverrides)
# Nothing else in the bottle (Steam included) is affected.
apply_dxvk_to_game() {
  local game_dir="$1" exe="$2" arch="${3:-x64}"
  [[ -d "$DXVK_DIR/$arch" ]] || die "DXVK $arch DLLs not found at $DXVK_DIR/$arch"
  for dll in "${DXVK_DLLS[@]}"; do
    [[ -f "$DXVK_DIR/$arch/${dll}.dll" ]] && cp -f "$DXVK_DIR/$arch/${dll}.dll" "$game_dir/${dll}.dll"
  done
  for dll in "${DXVK_DLLS[@]}"; do
    wine_run reg add "HKCU\\Software\\Wine\\AppDefaults\\${exe}\\DllOverrides" \
      /v "$dll" /d native /f >/dev/null 2>&1
  done
}

# --- Logging -----------------------------------------------------------------
# Per-game launch log. The app sets UNCORK_GAME_LOG to a per-game file so a launch
# leaves a diagnosable trail; unset (a manual run) it is /dev/null, i.e. unchanged.
# The launch scripts redirect the GAME process's own output here, and the helpers
# below mirror their narration here too, so there is a useful record even when Wine
# itself is quiet (WINEDEBUG=-all).
GAME_LOG="${UNCORK_GAME_LOG:-/dev/null}"
# Diagnostic relaunch: when the app requests it (UNCORK_DIAGNOSTIC=1) and the user
# has not pinned WINEDEBUG, raise the Wine log level so the game log captures Wine's
# OWN errors (dll load failures, HRESULTs, device-creation errors) instead of the
# near-silent default. Every launch site reads ${WINEDEBUG:--all}, so exporting it
# here reaches them all. fixme stays off: it floods the log without helping triage.
if [[ "${UNCORK_DIAGNOSTIC:-}" == "1" && -z "${WINEDEBUG:-}" ]]; then
  export WINEDEBUG="err+all,fixme-all"
fi
_glog() { [[ -n "${UNCORK_GAME_LOG:-}" ]] || return 0; printf '%s\n' "$*" >> "$UNCORK_GAME_LOG" 2>/dev/null || true; }
# Start a fresh log with a header (called once at the top of a launch).
game_log_init() {  # <header line>
  [[ -n "${UNCORK_GAME_LOG:-}" ]] || return 0
  mkdir -p "$(dirname "$UNCORK_GAME_LOG")" 2>/dev/null || true
  {
    printf '==== Uncork launch %s ====\n%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    [[ "${UNCORK_DIAGNOSTIC:-}" == "1" ]] && printf 'diagnostic mode on (WINEDEBUG=%s)\n' "${WINEDEBUG:-}"
    true
  } > "$UNCORK_GAME_LOG" 2>/dev/null || true
}

# Wine virtual-desktop launch prefix. When the app requests it (UNCORK_DESKTOP=WxH,
# the "Fullscreen (safe)" toggle) this expands to `explorer /desktop=Uncork,WxH` so
# the game runs in a borderless screen-sized Wine desktop instead of an exclusive
# fullscreen mode switch (which crashes many games on Wine/DXMT). Empty otherwise,
# so a game without the toggle launches exactly as before. Use UNQUOTED in the wine
# command so it word-splits into two args (or nothing).
desktop_prefix() { [[ -n "${UNCORK_DESKTOP:-}" ]] && printf 'explorer /desktop=Uncork,%s' "$UNCORK_DESKTOP" || true; }

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_off=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_blue"  "$c_off" "$*"; _glog "==> $*"; }
ok()   { printf '%s✓%s %s\n'  "$c_green" "$c_off" "$*"; _glog "[ok] $*"; }
warn() { printf '%s!%s %s\n'  "$c_yellow" "$c_off" "$*" >&2; _glog "[warn] $*"; }
die()  { printf '%s✗%s %s\n'  "$c_red"   "$c_off" "$*" >&2; _glog "[error] $*"; exit 1; }

# --- Download with progress --------------------------------------------------
# Download $1 -> $2, emitting real byte-progress as "@@STEP@@ <pct> <label>" lines
# the app parses for a live bar, with the percentage SCALED into the band [$3,$4]
# of the overall setup. Falls back to a static message if the server sends no
# Content-Length. Returns curl's exit status (so callers can `|| die`).
download_progress() {  # <url> <out> <lo> <hi> [label]
  local url="$1" out="$2" lo="$3" hi="$4" label="${5:-Downloading…}"
  local total got pct span cpid
  # Final Content-Length after following redirects (macOS awk: no IGNORECASE).
  total="$(curl -sIL "$url" 2>/dev/null | awk 'tolower($0) ~ /content-length:/ {v=$2} END{gsub(/[\r ]/,"",v); print v}')"
  span=$(( hi - lo ))
  curl -L --fail --silent --show-error "$url" -o "$out" &
  cpid=$!
  while kill -0 "$cpid" 2>/dev/null; do
    if [[ -n "$total" && "$total" -gt 0 && -f "$out" ]]; then
      got="$(stat -f %z "$out" 2>/dev/null || echo 0)"
      pct=$(( got * 100 / total )); [[ $pct -gt 100 ]] && pct=100
      printf '@@STEP@@ %s %s\n' "$(( lo + span * pct / 100 ))" "$label"
    else
      printf '@@STEP@@ %s %s\n' "$lo" "$label"
    fi
    sleep 0.4
  done
  wait "$cpid"
}

# --- Preflight ---------------------------------------------------------------
require_arm64() {
  [[ "$(uname -m)" == "arm64" ]] || die "This pipeline targets Apple Silicon (arm64)."
}

require_rosetta() {
  /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null && return 0
  # Not present: install it for the user (one-time). On a personal Mac this needs
  # no admin; on a policy-managed Mac it can be blocked, which we report honestly
  # rather than leaving the user at a dead end.
  printf '@@STEP@@ %s %s\n' 2 "Installing Rosetta 2 (one-time)…"
  log "Rosetta 2 not present; installing (one-time)…"
  softwareupdate --install-rosetta --agree-to-license >/dev/null 2>&1 || true
  if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
    ok "Rosetta 2 installed."
    return 0
  fi
  die "Rosetta 2 is required and could not be installed automatically. Install it with: softwareupdate --install-rosetta --agree-to-license"
}

# First-run preflight: fail early with a clear reason instead of deep in a download.
# Free disk space (GB) at the data dir; do not block if it cannot be determined.
preflight_disk() {  # [min-gb]
  local need="${1:-8}" path free
  path="${UNCORK_DATA:-$HOME/Library/Application Support}"
  free="$(df -g "$path" 2>/dev/null | awk 'NR==2 {print $4}')"
  [[ -n "$free" && "$free" -lt "$need" ]] \
    && die "Not enough free disk space: ${free} GB free, about ${need} GB needed. Free up space and retry."
  return 0
}

# Reachability: the first run has to download the engine, so a clear offline
# message beats a confusing curl failure later.
preflight_network() {
  curl -sI --max-time 8 https://github.com >/dev/null 2>&1 && return 0
  die "No internet connection. Uncork needs to download its engine on first run. Connect and retry."
}

require_wine() {
  # Fetch wine-stable on demand if it is not present (slim build / source clone).
  # Also self-heal a per-user engine that lacks DXMT: an older slim build fetched
  # stock Gcenx (no winemetal = no working DirectX 11), so re-fetch OUR engine over
  # it. Only ever refetch a DOWNLOADED engine (under the data dir), never the
  # read-only bundled payload, which always ships DXMT.
  local need=0
  [[ -x "$WINE_BIN" ]] || need=1
  if [[ "$WINE_HOME" == "$UNCORK_DATA_DIR"/* && ! -f "$WINE_HOME/lib/wine/x86_64-unix/winemetal.so" ]]; then
    need=1
  fi
  [[ "$need" == 1 ]] && bash "$PROJECT_ROOT/scripts/ensure-wine-engine.sh" wine-stable >&2 || true
  [[ -x "$WINE_BIN" ]] || die "Wine not found at $WINE_BIN. Run scripts/01-create-bottle.sh (or set WINE_URL/WINE_HOME)."
}

# Run a wine command against the MVP bottle, forced through Rosetta (x86-64).
# MVK_CONFIG_LOG_LEVEL=1 keeps MoltenVK to errors only (it's extremely chatty by default).
wine_run() {
  WINEPREFIX="$BOTTLE" WINEDEBUG="${WINEDEBUG:--all}" \
    MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}" \
    /usr/bin/arch -x86_64 "$WINE_BIN" "$@"
}

# Make sure $BOTTLE (selected via BOTTLE_NAME) exists and is DXMT-ready. Used for
# per-game isolated prefixes and custom (non-store) games. A fresh bottle picks
# up DXMT automatically because the graphics DLLs are builtins in the ENGINE;
# we just init the prefix and drop the winemetal bridge PE into its system32.
# Enable gamepad support in a Wine prefix. macOS has no hidraw backend (that is
# Linux only), so controllers must go through SDL, which winebus leaves OFF by
# default, so no game sees a gamepad. Turn SDL on and hidraw off. Idempotent via a
# per-prefix marker. Args: <prefix> <wine-binary>
enable_gamepad() {
  local prefix="$1" wine="${2:-$WINE_BIN}"
  [[ -f "$prefix/.uncork-gamepad" ]] && return 0
  for kv in "Enable SDL:1" "DisableHidraw:1"; do
    WINEPREFIX="$prefix" WINEDEBUG=-all "$wine" reg add \
      "HKLM\\System\\CurrentControlSet\\Services\\winebus" \
      /v "${kv%%:*}" /t REG_DWORD /d "${kv##*:}" /f >/dev/null 2>&1 || true
  done
  touch "$prefix/.uncork-gamepad" 2>/dev/null || true
}

ensure_bottle() {
  if [[ ! -d "$BOTTLE/drive_c" ]]; then
    log "Initializing bottle: $BOTTLE_NAME"
    mkdir -p "$BOTTLES_DIR"
    # Disable Mono/Gecko install prompts (they hang downloading on a fresh prefix).
    WINEPREFIX="$BOTTLE" WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=1 WINEDLLOVERRIDES="mscoree=;mshtml=" \
      /usr/bin/arch -x86_64 "$WINE_BIN" wineboot --init >/dev/null 2>&1 \
      || die "wineboot failed for bottle '$BOTTLE_NAME'."
    WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -w 2>/dev/null || true
  fi
  local wm="$WINE_HOME/lib/wine/x86_64-windows/winemetal.dll"
  [[ -f "$wm" && -d "$BOTTLE/drive_c/windows/system32" ]] && \
    cp -f "$wm" "$BOTTLE/drive_c/windows/system32/winemetal.dll" 2>/dev/null || true
  enable_gamepad "$BOTTLE" "$WINE_BIN"
}

# True only if a runtime install is ACTIVELY holding this bottle's lock. The lock
# records the installer's pid; a lock whose pid is gone (e.g. the installer was
# force-killed) is STALE: we remove it and report "not locked".
bottle_locked() {
  local lock="$BOTTLE/.uncork-runtime.lock" pid
  [[ -d "$lock" ]] || return 1
  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then return 0; fi
  rm -rf "$lock" 2>/dev/null || true   # stale -> clear it
  return 1
}

# --- Steam client lifecycle --------------------------------------------------
# Single source of truth for "is the bottle's Steam client running". Matches
# either slash direction: once Steam re-execs itself it reports a Windows-style
# path (Steam\steam.exe) that a '/'-only pattern misses, so we'd wrongly conclude
# it's down and start a SECOND client, which then fights the first over
# steamwebhelper (the "second instance / half-loaded" symptom). '.' matches / or \.
steam_is_up() { pgrep -f '[Ss]team.steam\.exe' >/dev/null 2>&1; }

# Bring the bottle's Steam client up exactly once, however many callers race. The
# app pre-warms Steam on open and a Play click starts it too; both can fire within
# the same second. The dangerous gap is between "we started Steam" and "Steam is
# visible to pgrep": a second caller checking in that gap sees nothing and starts
# a duplicate. An atomic mkdir lock closes it: whoever creates the lock owns the
# start and waits for Steam to appear; everyone else waits for that to finish. A
# lock older than the start budget is treated as stale (its owner crashed) and
# reclaimed. Returns 0 once Steam is up. Best-effort: never aborts a caller.
steam_ensure_running() {
  local steam_exe="$BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"
  [[ -f "$steam_exe" ]] || return 1
  steam_is_up && return 0

  local lock="$BOTTLE/.uncork-steam-start.lock"
  if [[ -d "$lock" ]]; then
    local age; age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || echo 0) ))
    (( age > 90 )) && rmdir "$lock" 2>/dev/null || true
  fi

  if mkdir "$lock" 2>/dev/null; then
    # We own the start. Re-check under the lock (another owner may have won the
    # race between our first check and taking the lock).
    if ! steam_is_up; then
      # Stop background auto-updates first (Wine + auto-update hangs shutdown);
      # it self-skips if Steam is already up. Then start hidden with software CEF
      # rendering (-cef-disable-gpu): the GPU compositor crash-loops steamwebhelper
      # under Wine and takes steam.exe down with it.
      STEAM_BOTTLE="$BOTTLE" bash "$(dirname "${BASH_SOURCE[0]}")/steam-tame.sh" >/dev/null 2>&1 || true
      wine_run "$steam_exe" -silent -no-browser -cef-disable-gpu >/dev/null 2>&1 &
    fi
    for _ in $(seq 1 30); do steam_is_up && break; sleep 1; done
    rmdir "$lock" 2>/dev/null || true
  else
    # Someone else owns the start; wait (bounded) for Steam to come up.
    for _ in $(seq 1 60); do steam_is_up && break; sleep 1; done
  fi
  steam_is_up
}
