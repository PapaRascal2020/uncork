#!/usr/bin/env bash
# install-location.sh - get or set where a store's games download, by symlinking
# the store's install root inside its Wine bottle to a folder the user picks. One
# symlink per store (the parent folder), so recorded per-game paths still resolve
# and both existing and future games live at the target.
#
#   install-location.sh get <epic|gog>
#   install-location.sh set <epic|gog> <path>
#
# Steam is not supported here: its libraries are managed by the Steam client.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

cmd="${1:?usage: install-location.sh <get|set> <epic|gog> [path]}"
store="${2:?store required}"
case "$store" in
  epic) bdir="epic"; sub="EpicGames" ;;
  gog)  bdir="gog";  sub="GOG Games" ;;
  *) die "install-location supports epic|gog only (Steam is managed by the Steam client)." ;;
esac
root="$BOTTLES_DIR/$bdir/drive_c/$sub"

case "$cmd" in
  get)
    if [[ -L "$root" ]]; then readlink "$root"
    elif [[ -d "$root" ]]; then echo "$root"
    else echo ""; fi
    ;;
  set)
    target="${3:?usage: install-location.sh set <store> <path>}"
    mkdir -p "$target" || die "Can't create $target"
    mkdir -p "$(dirname "$root")"
    if [[ -L "$root" ]]; then
      # Already redirected: move the old target's contents to the new one, repoint.
      old="$(readlink "$root")"
      if [[ -d "$old" && "$old" != "$target" ]]; then
        step 20 "Moving games to the new location…"
        ( shopt -s dotglob nullglob; mv "$old"/* "$target"/ 2>/dev/null || true )
      fi
      rm -f "$root"
    elif [[ -d "$root" ]]; then
      # A real folder (possibly with installed games): move its contents to the
      # target, then replace it with a symlink. mv is atomic on the same volume and
      # a copy+delete across volumes (so a big library can take a while).
      step 20 "Moving games to the new location…"
      ( shopt -s dotglob nullglob; mv "$root"/* "$target"/ 2>/dev/null || true )
      rmdir "$root" 2>/dev/null || rm -rf "$root"
    fi
    ln -s "$target" "$root" || die "Couldn't link the install location."
    step 100 "Install location set."
    ok "Games for '$store' now install to: $target"
    ;;
  *) die "usage: install-location.sh <get|set> <epic|gog> [path]" ;;
esac