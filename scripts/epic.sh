#!/usr/bin/env bash
# epic.sh: Epic Games via `legendary` (the lightweight CLI Epic client),
# configured to install/launch through Uncork's Wine engine. No Epic launcher,
# no CEF. Thin passthrough to legendary with our config preset.
#
#   ./scripts/epic.sh auth                  # one-time browser sign-in
#   ./scripts/epic.sh list-games            # your Epic library
#   ./scripts/epic.sh list-installed --json # installed Epic games (JSON)
#   ./scripts/epic.sh install <AppName>
#   ./scripts/epic.sh launch  <AppName>     # runs through wine-stable + bottle

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"   # D3DMetal launch helpers

# --- legendary (Epic CLI), RELOCATABLE ---------------------------------------
# The bundled legendary venv is a Python venv whose bin/ shebangs hardcode the
# BUILD machine's path, dead on any other Mac. But it was built against the
# system CLT Python (3.9.6, present on every Mac with Xcode CLT) and legendary is
# effectively pure Python, so we run it with the system python3 + the bundled
# packages on PYTHONPATH, invoking the console script directly (shebang ignored).
# This works on any Mac with no venv rebuild and no network.
# Prefer a bundled venv (payload); else the per-user one; provision it on demand
# if neither exists (a source clone ships no engine/). The python version dir is
# globbed, so it works whichever CLT python built the venv.
LEG_VENV="$ENGINE_DIR/legendary-venv"
[[ -x "$LEG_VENV/bin/legendary" ]] || LEG_VENV="$UNCORK_DATA_DIR/engine/legendary-venv"
[[ -x "$LEG_VENV/bin/legendary" ]] || bash "$(dirname "${BASH_SOURCE[0]}")/ensure-cli.sh" legendary >&2 || true
LEG_SCRIPT="$LEG_VENV/bin/legendary"
LEG_SP="$(ls -d "$LEG_VENV"/lib/python*/site-packages 2>/dev/null | head -1)"
PY="/usr/bin/python3"
[[ -f "$LEG_SCRIPT" && -d "$LEG_SP" ]] || die "legendary unavailable (could not provision it)."
[[ -x "$PY" ]] || die "Python 3 not found. Install the Xcode Command Line Tools: xcode-select --install"
LEG=(env "PYTHONPATH=$LEG_SP" "$PY" "$LEG_SCRIPT")

# Epic runs in its OWN bottle, separate from Steam. Steam and Epic games can
# need different Wine configs, and legendary (unlike Steam) needs no running
# client, so its own prefix keeps its config fully independent. The DXMT
# graphics stack is in the ENGINE, so this bottle is Metal-ready automatically.
BOTTLE_NAME="epic"
BOTTLE="$BOTTLES_DIR/$BOTTLE_NAME"

# legendary's config/state (auth token, installed.json). MUST be writable, so in
# a shipped app the app points this at ~/Library/Application Support/Uncork via
# the environment; the dev default keeps it beside the venv.
export LEGENDARY_CONFIG_PATH="${LEGENDARY_CONFIG_PATH:-$ENGINE_DIR/legendary}"
mkdir -p "$LEGENDARY_CONFIG_PATH"

# Point legendary at the Epic bottle + our bundled Wine.
#   - disable_auto_crossover: on macOS legendary tries to launch via CrossOver by
#     default and CRASHES (IndexError at core.py get_app_launch_command) when no
#     CrossOver is installed. We use our own Wine, so turn that off.
#   - wine_executable MUST live under [default] (that's where legendary reads it
#     for launch); putting it under [Legendary] means it falls back to bare 'wine'.
CFG="$LEGENDARY_CONFIG_PATH/config.ini"
new_cfg="$(cat <<EOF
[Legendary]
disable_auto_crossover = true
install_dir = $BOTTLE/drive_c/EpicGames

[default]
wine_executable = $WINE_BIN

[default.env]
WINEPREFIX = $BOTTLE
EOF
)"
# Write ONCE (only if missing). legendary owns config.ini after that: it
# rewrites it to its canonical form on every run and snapshots the old one to
# config.<timestamp>.ini, so re-writing it each call spams dozens of backups.
# Launch correctness doesn't depend on this file anyway (we pass --wine below).
if [[ ! -f "$CFG" ]]; then
  printf '%s\n' "$new_cfg" > "$CFG"
fi

# --- D3DMetal launch: bypass `legendary launch` -----------------------------
# legendary's launcher rewrites the graphics environment (drops our D3DMetal
# DLL overrides), so the game falls to Wine's wined3d D3D9 → pink/blank screen.
# So when D3DMetal is available we resolve the exe from installed.json and run it
# DIRECTLY through GPTk Wine with our env intact, the path proven to hit
# D3DMetal (D3D11, "AMD Compatibility Mode"). legendary still handles list/install.
if [[ "${1:-}" == "launch" ]] && gptk_available && [[ "${UNCORK_BACKEND:-d3dmetal}" == "d3dmetal" ]]; then
  app="${2:?usage: epic.sh launch <app_name>}"
  read_field() { python3 -c "import json,sys; print(json.load(open('$LEGENDARY_CONFIG_PATH/installed.json')).get('$app',{}).get(sys.argv[1],''))" "$1" 2>/dev/null; }
  ipath="$(read_field install_path)"; iexe="$(read_field executable)"
  [[ -n "$ipath" && -f "$ipath/$iexe" ]] || die "Epic game '$app' isn't installed (no exe under install_path)."
  ensure_gptk_prefix epic
  gptk_export_env
  game_log_init "Epic $app, exe $iexe, backend d3dmetal"
  status "Launching via D3DMetal…" 2>/dev/null || true
  log "Launching '$app' via D3DMetal (GPTk): $iexe"
  cd "$ipath"
  exec "$GPTK_WINE" "$iexe" >>"$GAME_LOG" 2>&1
fi

# Commands that actually run Wine need the Epic bottle to exist + be DXMT-ready.
case "${1:-}" in
  launch|install|download|update|repair|verify) ensure_bottle ;;
esac

# Uncork runs Windows games via Wine, so operate on the WINDOWS library, not
# just the handful of titles that happen to ship a native macOS build (which is
# what legendary shows by default on a Mac). Without this, most of a user's
# library (e.g. For The King, Cities Skylines) is invisible. Inject the platform
# for the commands where it matters, unless the caller already set one.
args=("$@")
case "${1:-}" in
  list-games|install|info|download|update|repair|verify)
    if ! printf '%s\0' "$@" | grep -qzE '^--platform$|^-P$'; then
      args+=(--platform Windows)
    fi
    ;;
esac
# Fallback launch, only reached when D3DMetal isn't available (the D3DMetal path
# above exec's directly). Use our bundled Wine; --wine is REQUIRED or legendary
# auto-detects CrossOver on macOS and crashes (IndexError) when none is present.
if [[ "${1:-}" == "launch" ]]; then
  log "Graphics: bundled Wine (DXMT/DXVK) - D3DMetal not installed"
  printf '%s\0' "$@" | grep -qzE '^--wine$' || args+=(--wine "$WINE_BIN")
fi
exec "${LEG[@]}" "${args[@]}"
