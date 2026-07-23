#!/usr/bin/env bash
# Step 5: make Steam's CEF UI render (fix the black login/library windows).
#
# Compiles the steamwebhelper wrapper and installs it over every
# steamwebhelper.exe in the bottle, so CEF runs with --disable-gpu
# --single-process (which winemac can actually present).
#
# Requires mingw-w64 (x86_64-w64-mingw32-gcc). If missing, this prints how to
# get it. Idempotent: safe to re-run (won't double-rename the real binary).
#
# Usage:  ./scripts/05-fix-steam-rendering.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_wine
STEAM_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam"
[[ -d "$STEAM_ROOT" ]] || die "Steam not installed. Run scripts/03-install-steam.sh first."

WRAPPER_SRC="$PROJECT_ROOT/scripts/wrapper/steamwebhelper-wrapper.c"
WRAPPER_EXE="$ENGINE_DIR/steamwebhelper-wrapper.exe"
MINGW="${MINGW:-x86_64-w64-mingw32-gcc}"

# --- Build the wrapper -------------------------------------------------------
if ! command -v "$MINGW" >/dev/null 2>&1; then
  cat >&2 <<EOF
$(printf '%s✗%s' "$c_red" "$c_off") mingw-w64 not found ($MINGW).

  Install it (one-time), then re-run this script:

    # 1) Homebrew, if you don't have it (needs your admin password):
    /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # 2) the Windows cross-compiler:
    brew install mingw-w64
EOF
  exit 1
fi

# --- Stop Steam clobbering our wrapper --------------------------------------
# Steam verifies its client files each launch; our modified steamwebhelper.exe
# looks "corrupt", so it re-extracts the package and overwrites the wrapper.
# steam.cfg inhibits the bootstrapper's self-repair/update so the wrapper sticks.
log "Writing steam.cfg to inhibit bootstrapper self-repair"
printf 'BootStrapperInhibitAll=enable\nBootStrapperForceSelfUpdate=disable\n' > "$STEAM_ROOT/steam.cfg"
ok "steam.cfg written"

log "Compiling steamwebhelper wrapper"
"$MINGW" -municode -O2 -Wall -Wextra -static -mwindows \
  -o "$WRAPPER_EXE" "$WRAPPER_SRC" || die "Wrapper compile failed."
ok "Built: $WRAPPER_EXE"

# --- Install over each steamwebhelper.exe ------------------------------------
# bash 3.2 (macOS default) has no mapfile, so read into an array portably.
helpers=()
while IFS= read -r line; do helpers+=("$line"); done < <(find "$STEAM_ROOT" -type f -name 'steamwebhelper.exe' 2>/dev/null)
[[ ${#helpers[@]} -gt 0 ]] || die "No steamwebhelper.exe found under $STEAM_ROOT (has Steam finished updating?)."

installed=0
for helper in "${helpers[@]}"; do
  dir="$(dirname "$helper")"
  real="$dir/steamwebhelper_real.exe"
  # Only rename the genuine helper once; if real already exists this is a re-run.
  if [[ ! -f "$real" ]]; then
    mv "$helper" "$real"
  fi
  cp -f "$WRAPPER_EXE" "$dir/steamwebhelper.exe"
  printf '    wrapped: %s\n' "${dir#"$BOTTLE/drive_c/"}"
  installed=$((installed+1))
done
ok "Installed wrapper over $installed steamwebhelper.exe location(s)"

echo
ok "Step 5 complete."
echo "    Relaunch Steam:  ./scripts/steam.sh"
echo "    The login window should now RENDER (CEF forced to single-process/software)."
echo "    Note: a future Steam self-update may restore the original helper - just re-run this."
