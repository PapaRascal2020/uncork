#!/usr/bin/env bash
# gog.sh: GOG via `gogdl` (Heroic's GOG CLI, same author as legendary). GOG is
# DRM-free, so there's no client to run: games install into the shared "gog"
# bottle and launch directly on D3DMetal (like Epic). Thin passthrough to gogdl
# with our config preset.
#
#   ./scripts/gog.sh status                 # signed in?
#   ./scripts/gog.sh auth --code <CODE>      # one-time sign-in (browser code)
#   ./scripts/gog.sh info <id> --platform windows
#   ./scripts/gog.sh download <id> --platform windows --path <dir>
#   ./scripts/gog.sh launch <path> <id>      # runs via GPTk Wine + D3DMetal

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"   # D3DMetal launch helpers

# --- gogdl (GOG CLI), RELOCATABLE ------------------------------------------
# Same trick as legendary (see epic.sh): the bundled venv's shebangs hardcode the
# build machine's path, so we run gogdl with the system CLT python3 (3.9) + the
# bundled packages on PYTHONPATH, invoking the console script directly. Works on
# any Mac with the Xcode Command Line Tools, no venv rebuild, no network.
# Prefer a bundled venv (payload); else the per-user one; provision on demand if
# neither exists (a source clone ships no engine/). Python version dir is globbed.
GOG_VENV="$ENGINE_DIR/gogdl-venv"
[[ -x "$GOG_VENV/bin/gogdl" ]] || GOG_VENV="$UNCORK_DATA_DIR/engine/gogdl-venv"
[[ -x "$GOG_VENV/bin/gogdl" ]] || bash "$(dirname "${BASH_SOURCE[0]}")/ensure-cli.sh" gogdl >&2 || true
GOG_SCRIPT="$GOG_VENV/bin/gogdl"
GOG_SP="$(ls -d "$GOG_VENV"/lib/python*/site-packages 2>/dev/null | head -1)"
PY="/usr/bin/python3"
[[ -f "$GOG_SCRIPT" && -d "$GOG_SP" ]] || die "gogdl unavailable (could not provision it)."
[[ -x "$PY" ]] || die "Python 3 not found. Install the Xcode Command Line Tools: xcode-select --install"
GOGDL=(env "PYTHONPATH=$GOG_SP" "$PY" "$GOG_SCRIPT")

# GOG games share ONE bottle (a launcher's whole library lives in its own bottle,
# per Uncork's bottle model). DRM-free games are Metal-ready via the engine.
BOTTLE_NAME="gog"
BOTTLE="$BOTTLES_DIR/$BOTTLE_NAME"

# gogdl stores its OAuth tokens in a json file we pass via --auth-config-path.
# MUST be writable, so the app points UNCORK_DATA at App Support; dev default
# keeps it beside the engine.
GOGDL_CONFIG_PATH="${GOGDL_CONFIG_PATH:-${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/gogdl}"
mkdir -p "$GOGDL_CONFIG_PATH"
AUTH="$GOGDL_CONFIG_PATH/auth.json"

# --- lightweight commands that don't need Wine -----------------------------
case "${1:-}" in
  status)
    # Signed in if the token file has an access_token. (gogdl refreshes on use.)
    if [[ -s "$AUTH" ]] && grep -q '"access_token"' "$AUTH" 2>/dev/null; then
      echo "GOG account: signed in"
    else
      echo "GOG account: <not logged in>"
    fi
    exit 0 ;;
  auth)
    # gog.sh auth --code <CODE>  → exchange the browser code for tokens.
    shift
    exec "${GOGDL[@]}" --auth-config-path "$AUTH" auth "$@" ;;
  uninstall)
    # gog.sh uninstall <id>: GOG is DRM-free with no registration, so removing a
    # game is just deleting its install dir (located via its goggame-<id>.info).
    gid="${2:?usage: gog.sh uninstall <id>}"
    info="$(find "$BOTTLE/drive_c/GOG Games" -name "goggame-$gid.info" 2>/dev/null | head -1)"
    if [[ -n "$info" ]]; then
      rm -rf "$(dirname "$info")" && ok "Uninstalled GOG game $gid." || die "Couldn't remove GOG game $gid."
    else
      warn "GOG game $gid doesn't appear to be installed."
    fi
    exit 0 ;;
  save-sync)
    # gog.sh save-sync <id> <save-path> <last-ts> [up|down|auto]
    # Two-way GOG cloud save sync via gogdl. The app owns the per-game save folder
    # and last-sync timestamp (cloud-saves.json) and passes them in, so this stays
    # stateless. --os windows: we run the Windows build under Wine, so saves live in
    # the Windows profile inside the bottle. No Wine needed to sync, so it's here in
    # the early (client-free) dispatch.
    gid="${2:?usage: gog.sh save-sync <id> <save-path> <last-ts> [up|down|auto]}"
    spath="${3:?save-path required}"
    ts="${4:-0}"; mode="${5:-auto}"
    [[ -d "$spath" ]] || die "Save folder not found: $spath"
    gargs=(--auth-config-path "$AUTH" save-sync "$spath" "$gid" --os windows --ts "$ts")
    case "$mode" in
      up)   gargs+=(--skip-download) ;;
      down) gargs+=(--skip-upload) ;;
    esac
    exec "${GOGDL[@]}" "${gargs[@]}" ;;
  library)
    # Owned GOG games as JSON [{id,title,cover}]; gogdl has no list-games, so we
    # query GOG's account API with the stored token. (Token is fresh right after
    # sign-in; refresh handling is a follow-up.)
    [[ -s "$AUTH" ]] || { echo "[]"; exit 0; }
    exec "$PY" - "$AUTH" <<'PY'
import json,sys,urllib.request
try:
    auth=json.load(open(sys.argv[1]))
except Exception:
    print("[]"); sys.exit(0)
def find_token(o):
    if isinstance(o,dict):
        if 'access_token' in o: return o['access_token']
        for v in o.values():
            t=find_token(v)
            if t: return t
    return None
tok=find_token(auth); out=[]
if tok:
    page=1
    while True:
        req=urllib.request.Request('https://embed.gog.com/account/getFilteredProducts?mediaType=1&page=%d'%page,
                                   headers={'Authorization':'Bearer '+tok})
        try:
            d=json.load(urllib.request.urlopen(req,timeout=25))
        except Exception:
            break
        for p in d.get('products',[]):
            img=p.get('image') or ''
            if img.startswith('//'): cover='https:'+img+'.jpg'
            elif img: cover=img+'.jpg'
            else: cover=''
            # worksOn: {Windows,Mac,Linux} booleans → lets Uncork show native Mac
            # builds in the Library's Mac tab (GOG ships real macOS builds for many).
            works=p.get('worksOn',{}) or {}
            out.append({'id':str(p.get('id','')),'title':p.get('title',''),'cover':cover,
                        'worksOn':{'Windows':bool(works.get('Windows')),'Mac':bool(works.get('Mac')),'Linux':bool(works.get('Linux'))}})
        if page>=int(d.get('totalPages',1) or 1): break
        page+=1
print(json.dumps(out))
PY
    ;;
esac

# Commands that touch a game need the GOG bottle to exist + be Metal-ready.
case "${1:-}" in
  launch|download|repair|update|info) ensure_bottle 2>/dev/null || true ;;
esac

# --- D3DMetal launch: direct-run the exe (bypass gogdl's env rewrite) -------
# Like Epic, prefer D3DMetal (GPTk) when available: resolve the game's exe and
# run it directly through GPTk Wine with our graphics env intact. gogdl still
# handles auth/download/info. (GOG is DRM-free, so no client needs to be running.)
if [[ "${1:-}" == "launch" ]] && gptk_available && [[ "${UNCORK_BACKEND:-d3dmetal}" == "d3dmetal" ]]; then
  gpath="${2:?usage: gog.sh launch <install_path> <id>}"
  gid="${3:-}"
  # NATIVE macOS build? If a .app is present in the install dir, launch it DIRECTLY
  # no Wine, no D3DMetal. This is how a GOG native Mac game runs (installed via
  # `download --platform osx`). Detecting the .app means the same launch path works
  # whether the Windows or the Mac build was installed.
  app="$(cd "$gpath" 2>/dev/null && find . -maxdepth 3 -iname '*.app' -type d | head -1)"
  if [[ -n "$app" ]]; then
    status "Launching native macOS build…" 2>/dev/null || true
    log "Launching GOG native Mac app: ${app#./}"
    cd "$gpath"; exec /usr/bin/open "$app"
  fi
  # Ask gogdl for the launch command (exe + args) as JSON, then run the exe via GPTk.
  ensure_gptk_prefix gog
  gptk_export_env
  exe="$(cd "$gpath" 2>/dev/null && find . -maxdepth 2 -iname '*.exe' | grep -viE 'unins|redist|vcredist|dxsetup|dotnet|crashreport' | head -1)"
  if [[ -n "$exe" ]]; then
    game_log_init "GOG ${gpath##*/} (id ${gid:-?}), exe ${exe##*/}, backend d3dmetal"
    status "Launching via D3DMetal…" 2>/dev/null || true
    log "Launching GOG game via D3DMetal (GPTk): $exe"
    cd "$gpath"; exec "$GPTK_WINE" "$exe" ${UNCORK_LAUNCH_ARGS:-} >>"$GAME_LOG" 2>&1
  fi
  warn "Couldn't resolve a game exe under '$gpath'; falling back to gogdl launch."
fi

# Explicit DXMT backend (the compat dropdown): direct-run the exe through our
# bundled Wine with the DXMT/Metal env + the user's launch args, mirroring the
# Steam DXMT path. ensure_bottle above put the winemetal bridge in system32.
if [[ "${1:-}" == "launch" && "${UNCORK_BACKEND:-}" == "dxmt" ]]; then
  gpath="${2:?usage: gog.sh launch <install_path> <id>}"; gid="${3:-}"
  exe="$(cd "$gpath" 2>/dev/null && find . -maxdepth 2 -iname '*.exe' | grep -viE 'unins|redist|vcredist|dxsetup|dotnet|crashreport' | head -1)"
  [[ -n "$exe" ]] || die "Couldn't resolve a game exe under '$gpath'."
  game_log_init "GOG ${gpath##*/} (id ${gid:-?}), exe ${exe##*/}, backend dxmt"
  cd "$gpath"
  for d in d3d11 dxgi d3d10core d3d9 d3d8 winemetal; do rm -f "$(dirname "$exe")/$d.dll" 2>/dev/null || true; done
  status "Launching via DXMT…" 2>/dev/null || true
  log "Launching GOG game via DXMT (bundled Wine): $exe"
  env WINEPREFIX="$BOTTLE" WINEDEBUG="${WINEDEBUG:--all}" MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}" \
      WINEDLLOVERRIDES="d3d11,dxgi,d3d10core=b" \
      DYLD_FALLBACK_LIBRARY_PATH="$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}" \
      /usr/bin/arch -x86_64 "$WINE_BIN" "$exe" ${UNCORK_LAUNCH_ARGS:-} >>"$GAME_LOG" 2>&1
  exit $?
fi

# Fallback / non-launch passthrough. Use our bundled Wine for gogdl launch.
args=("$@")
if [[ "${1:-}" == "launch" ]]; then
  printf '%s\0' "$@" | grep -qzE '^--wine$' || args+=(--wine "$WINE_BIN")
  printf '%s\0' "$@" | grep -qzE '^--wine-prefix$' || args+=(--wine-prefix "$BOTTLE")
  printf '%s\0' "$@" | grep -qzE '^--platform$|^--os$' || args+=(--platform windows)
fi
# download/repair/update <id> → default to Windows into the shared GOG bottle's
# "GOG Games" dir. repair (a download alias in gogdl) REQUIRES --path, so it must
# get the same base path the install used, or it errors.
case "${1:-}" in download|repair|update)
  printf '%s\0' "$@" | grep -qzE '^--platform$|^--os$' || args+=(--platform windows)
  if ! printf '%s\0' "$@" | grep -qzE '^--path$'; then
    mkdir -p "$BOTTLE/drive_c/GOG Games"
    args+=(--path "$BOTTLE/drive_c/GOG Games")
  fi
  ;;
esac
exec "${GOGDL[@]}" --auth-config-path "$AUTH" "${args[@]}"
