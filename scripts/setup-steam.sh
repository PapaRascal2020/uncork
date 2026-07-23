#!/usr/bin/env bash
# setup-steam.sh - provision Steam in Uncork, reliably.
#
# WHY NOT let Steam self-install: Steam's own bootstrapper can't reach the CDN
# from inside Wine (the manifest fetch dies with "http error 0"), so a fresh
# install never completes (staging packages doesn't help; Steam won't install
# them without the manifest it can't fetch). The Mac's network is fine; it's
# Wine's HTTP that fails.
#
# WHAT WE DO instead: create the bottle, then RESTORE a pre-built, already-
# installed Steam client SNAPSHOT that carries the `.installed` markers and a
# `steam.cfg` (BootStrapperInhibitAll) so Steam skips the (broken) self-update
# and boots straight to the login window. The snapshot (~2 GB) is NOT bundled;
# on first run it's DOWNLOADED into the writable per-user dir from
# STEAM_CLIENT_SNAPSHOT_URL and unpacked (same pattern as ensure-engine.sh/GPTk).
#
# HOSTING: build the tarball once with
#   tar -czf steam-client-snapshot.tar.gz -C <engine-dir> steam-client-snapshot
# upload it somewhere durable, and set STEAM_CLIENT_SNAPSHOT_URL below (or via
# env) to that URL. The default below is a PLACEHOLDER, replace it.
#
# Emits @@STEP@@ <pct> <msg> progress. Idempotent.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"   # store_prereqs, gptk_baseline_verbs
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"       # ensure_gptk_baseline

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

STEAM_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_ROOT/steam.exe"
INSTALLED_MARKER="$STEAM_ROOT/package/steam_client_win64.installed"

# Where the pre-built client snapshot lives (writable per-user dir first, then a
# dev/bundled fallback). If it's absent, we DOWNLOAD it on first run from
# STEAM_CLIENT_SNAPSHOT_URL; the client is ~2 GB so it's fetched, not bundled
# (same approach as the GPTk graphics engine in ensure-engine.sh).
SNAPSHOT_USER_DIR="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/engine/steam-client-snapshot"
SNAPSHOT="${STEAM_CLIENT_SNAPSHOT:-$SNAPSHOT_USER_DIR}"
[[ -d "$SNAPSHOT/package" ]] || SNAPSHOT="$ENGINE_DIR/steam-client-snapshot"
# The hosted snapshot tarball (gzip'd `steam-client-snapshot/` dir). Overridable.
STEAM_CLIENT_SNAPSHOT_URL="${STEAM_CLIENT_SNAPSHOT_URL:-https://github.com/PapaRascal2020/uncork/releases/download/steam-client/steam-client-snapshot.tar.gz}"

step 5 "Checking your Mac…"
require_arm64
require_rosetta
require_wine

step 15 "Preparing the Steam bottle…"
ensure_bottle           # wineboot --init + winemetal bridge; idempotent

# --- Provision the Steam client (restore the pre-built snapshot) ------------
if [[ -f "$STEAM_EXE" && -f "$INSTALLED_MARKER" && -f "$STEAM_ROOT/steam.cfg" ]]; then
  ok "Steam client already provisioned."
else
  # Fetch the snapshot on demand if it's not already on disk (first run only).
  if [[ ! -d "$SNAPSHOT/package" && -n "$STEAM_CLIENT_SNAPSHOT_URL" ]]; then
    step 20 "Downloading the Steam client (first run, ~1 GB)…"
    mkdir -p "$SNAPSHOT_USER_DIR"
    parent="$(dirname "$SNAPSHOT_USER_DIR")"; tb="$parent/steam-client-snapshot.tar.gz"
    download_progress "$STEAM_CLIENT_SNAPSHOT_URL" "$tb" 20 42 "Downloading the Steam client…" \
      || die "Couldn't download the Steam client. Check your connection and retry."
    step 44 "Unpacking the Steam client…"
    # The tarball contains a top-level steam-client-snapshot/ dir → extract into
    # the parent so it lands exactly at SNAPSHOT_USER_DIR.
    ( cd "$parent" && tar -xf "$tb" ) || die "Couldn't unpack the Steam client."
    rm -f "$tb"
    SNAPSHOT="$SNAPSHOT_USER_DIR"
  fi

  if [[ -d "$SNAPSHOT/package" ]]; then
    step 46 "Installing the Steam client…"
    mkdir -p "$STEAM_ROOT"
    # Clone the pre-built client into the bottle (APFS clone → instant, no copy).
    ( cd "$SNAPSHOT" && for item in *; do
        cp -Rc "$item" "$STEAM_ROOT/" 2>/dev/null || cp -R "$item" "$STEAM_ROOT/"
      done )
    step 52 "Verifying the Steam client…"
    for need in "$STEAM_EXE" "$STEAM_ROOT/steam.cfg" "$INSTALLED_MARKER"; do
      [[ -e "$need" ]] || die "Steam client incomplete (missing ${need##*/}). Please retry."
    done
    ok "Steam client provisioned (self-update inhibited)."
  else
    die "No Steam client snapshot on disk and STEAM_CLIENT_SNAPSHOT_URL isn't set/reachable. Host steam-client-snapshot.tar.gz and set STEAM_CLIENT_SNAPSHOT_URL (see script header)."
  fi
fi

# --- Steam-client prerequisites into the client bottle (data-driven) --------
prereqs=()
while IFS= read -r v; do [[ -n "$v" ]] && prereqs+=("$v"); done < <(store_prereqs steam)
if [[ ${#prereqs[@]} -gt 0 ]]; then
  n=${#prereqs[@]}; i=0
  for verb in "${prereqs[@]}"; do
    i=$((i+1))
    step $(( 55 + (i - 1) * 10 / n )) "Installing ${verb}…"
    BOTTLE_NAME=steam bash "$(dirname "${BASH_SOURCE[0]}")/install-runtime.sh" "$verb" \
      || warn "Component '$verb' didn't install cleanly - Steam still works; retry later."
  done
fi

# --- Baseline game libraries into the D3DMetal prefix (steam-gptk) ----------
# So most Steam games run on D3DMetal with no per-game config (emits @@STEP@@ 70→95).
if gptk_available; then ensure_gptk_baseline steam; fi

step 100 "Steam is ready - sign in next."
ok "Steam provisioned: $STEAM_EXE"
