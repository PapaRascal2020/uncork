#!/usr/bin/env bash
# steam-cef-shim.sh - install the steamwebhelper CEF wrapper into the Steam bottle.
#
# WHY: Steam's CEF UI renders black on Apple Silicon because Wine's multi-process CEF
# GPU/compositor path can't present to winemac's surface, and its out-of-process
# NetworkService also breaks the login TLS handshake. The wrapper replaces
# steamwebhelper.exe and relaunches the backed-up real client with
# --disable-gpu --single-process, which fixes BOTH the black window and sign-in.
# We install the proven wrapper (scripts/wrapper/steamwebhelper-wrapper.c, adapted
# from notpop/steam-on-m1-wine, MIT) that is verified to render AND log in.
#
# Bottle-scoped. Idempotent. The launch must add -noverifyfiles (steam.sh does) so
# Steam does not revert the wrapper; we also set the immutable flag as a second guard.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

BOTTLE_NAME="steam"
BOTTLE="$BOTTLES_DIR/$BOTTLE_NAME"
CEF_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam/bin/cef"
SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wrapper"
SHIM64="$SHIM_DIR/steamwebhelper-wrapper-64.exe"
SHIM32="$SHIM_DIR/steamwebhelper-wrapper-32.exe"

[[ -d "$CEF_ROOT" ]] || die "Steam's CEF runtime isn't present yet (install/complete Steam first)."
[[ -f "$SHIM64" ]] || die "Wrapper binary missing: $SHIM64 (build from scripts/wrapper/steamwebhelper-wrapper.c)."

# Install the arch-appropriate shim into one cef variant dir.
install_one() {  # <cef-dir> <shim>
  local dir="$1" shim="$2"
  local swh="$dir/steamwebhelper.exe" real="$dir/steamwebhelper_real.exe"
  [[ -f "$swh" || -f "$real" ]] || return 0        # this variant isn't installed
  # Back up the genuine client ONCE (never overwrite the backup with our shim).
  if [[ ! -f "$real" && -f "$swh" ]]; then
    cp "$swh" "$real" || die "Couldn't back up ${dir##*/}/steamwebhelper.exe"
  fi
  chflags nouchg "$swh" 2>/dev/null || true        # our own immutable flag from a prior run
  cp "$shim" "$swh" || die "Couldn't install shim into ${dir##*/}"
  chflags uchg "$swh" 2>/dev/null || true          # stop Steam overwriting it
  echo "    shimmed ${dir##*/}"
}

step 30 "Installing the Steam rendering fix (single-process CEF)…"
# cef.win64 / cef.win7x64 are 64-bit; cef.win7 is 32-bit.
install_one "$CEF_ROOT/cef.win64"   "$SHIM64"
install_one "$CEF_ROOT/cef.win7x64" "$SHIM64"
install_one "$CEF_ROOT/cef.win7"    "$SHIM32"

step 100 "Rendering fix installed."
ok "Installed the single-process CEF shim. Steam must launch with -noverifyfiles (steam.sh does)."
