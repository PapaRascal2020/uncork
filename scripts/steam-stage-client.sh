#!/usr/bin/env bash
# steam-stage-client.sh - complete a stalled Steam client install by fetching the
# OFFICIAL client packages from Valve's CDN with the Mac's native networking, then
# letting Steam's OWN bootstrapper install them.
#
# WHY: Steam's in-Wine downloader is unreliable, so the self-update stalls and the
# client stays half-installed (black login window). The Mac's network is fine; only
# Wine's HTTP is the problem. So we fetch the exact packages Steam's own bootstrapper
# asks for and stage them in Steam's own package/ dir; the official bootstrapper then
# installs from those local files (no in-Wine download) and writes its .installed
# markers, producing a complete, working client.
#
# LEGAL: Uncork hosts and redistributes NOTHING. Every byte is pulled from Valve's
# official CDN to the user's own machine over public, unauthenticated HTTPS, the same
# files Steam's own installer downloads. We only assist the official client's own
# update by completing its download; we never ship, mirror, or repackage the client.
#
# Emits @@STEP@@ progress. Idempotent (skips packages already present at full size).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

BOTTLE_NAME="steam"
BOTTLE="$BOTTLES_DIR/$BOTTLE_NAME"
STEAM_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_ROOT/steam.exe"
PKG="$STEAM_ROOT/package"
# Valve's official client CDN (from Steam's own bootstrap log). Overridable only for
# a mirror or testing; the default is Valve's.
CDN="${STEAM_CLIENT_CDN:-https://cdn.steamstatic.com/client}"
CACHE="${UNCORK_CACHE:-${TMPDIR:-/tmp}/uncork-cache}"

require_wine
[[ -f "$STEAM_EXE" ]] || die "Steam isn't installed yet (no bootstrapper). Run Steam setup first."
mkdir -p "$PKG" "$CACHE"
preflight_network
preflight_disk 3

# --- 1) Read Valve's package manifests, build the download list ---------------
# The Wine client is 32-bit; it also pulls some win64 packages. We union both
# manifests to match a complete client. Per package we take the compressed 'zipvz'
# when present (smaller), else the plain 'file'. We also capture the expected size
# so we can verify each download (Steam rejects a wrong-size package and would then
# try to re-download it in-Wine, which is the failure we are avoiding).
step 4 "Reading Steam's package list from Valve…"
LIST="$CACHE/steam-stage-list.txt"; : > "$LIST"
got_manifest=0
for m in steam_client_win32 steam_client_win64; do
  mf="$CACHE/$m.manifest"
  curl -fsSL --max-time 60 "$CDN/$m" -o "$mf" 2>/dev/null || { warn "Manifest $m unavailable, skipping."; continue; }
  got_manifest=1
  file=""; zipvz=""; size=""
  while IFS= read -r line; do
    case "$line" in
      *"{"*) file=""; zipvz=""; size="" ;;
      *'"file"'*)  file="$(printf '%s' "$line"  | sed -n 's/.*"file"[[:space:]]*"\([^"]*\)".*/\1/p')" ;;
      *'"size"'*)  size="$(printf '%s' "$line"  | sed -n 's/.*"size"[[:space:]]*"\([^"]*\)".*/\1/p')" ;;
      *'"zipvz"'*) zipvz="$(printf '%s' "$line" | sed -n 's/.*"zipvz"[[:space:]]*"\([^"]*\)".*/\1/p')" ;;
      *"}"*)
        if [[ -n "$zipvz" ]]; then
          printf '%s\t%s\n' "$zipvz" "${zipvz##*_}" >> "$LIST"    # vz size is the _<size> suffix
        elif [[ -n "$file" ]]; then
          printf '%s\t%s\n' "$file" "$size" >> "$LIST"
        fi
        file=""; zipvz=""; size="" ;;
    esac
  done < "$mf"
done
[[ "$got_manifest" == 1 ]] || die "Couldn't reach Valve's client CDN to read the package list."
# Dedupe (both manifests can list the same package).
sort -u "$LIST" -o "$LIST"
total="$(grep -c . "$LIST" || echo 0)"
[[ "$total" -gt 0 ]] || die "Valve's manifest listed no packages (unexpected)."

# --- 2) Download each package from Valve's CDN into Steam's package/ ----------
i=0
while IFS=$'\t' read -r name want; do
  [[ -n "$name" ]] || continue
  i=$((i+1))
  step $(( 8 + (i-1)*70/total )) "Downloading the Steam client from Valve ($i/$total)…"
  out="$PKG/$name"
  cur="$(stat -f%z "$out" 2>/dev/null || echo 0)"
  if [[ -f "$out" && -n "$want" && "$cur" == "$want" ]]; then continue; fi   # already have it
  curl -fsSL --max-time 900 "$CDN/$name" -o "$out" || die "Download failed from Valve: $name"
  if [[ -n "$want" ]]; then
    cur="$(stat -f%z "$out" 2>/dev/null || echo 0)"
    [[ "$cur" == "$want" ]] || die "Size mismatch for $name (got $cur, expected $want)."
  fi
done < "$LIST"

# --- 3) Let Steam's OWN bootstrapper install the staged packages --------------
step 82 "Installing the client (Steam does this itself)…"
WINEMSYNC=0 WINEESYNC=0 wine_run "$STEAM_EXE" -silent -no-browser -cef-disable-gpu >/dev/null 2>&1 &
installed=0
for _ in $(seq 1 300); do          # up to ~10 min; installing from local packages is fast
  if compgen -G "$PKG/steam_client_win*.installed" >/dev/null 2>&1 && [[ -d "$STEAM_ROOT/bin/cef" ]]; then
    installed=1; break
  fi
  sleep 2
done

step 92 "Finishing up…"
WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true
sleep 1
# Freeze further self-updates so the completed client boots straight to login with
# our -cef-disable-gpu flag (see steam.sh) instead of re-updating and self-relaunching.
printf 'BootStrapperInhibitAll=enable\nBootStrapperForceSelfUpdate=disable\n' > "$STEAM_ROOT/steam.cfg"

if [[ "$installed" == 1 ]]; then
  step 100 "Steam client ready."
  ok "Completed the official Steam client from Valve's CDN. Sign in next."
else
  warn "Staged the packages, but couldn't confirm the install finished. Open Steam once more; it should complete from the local packages."
fi
