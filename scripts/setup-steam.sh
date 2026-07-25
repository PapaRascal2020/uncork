#!/usr/bin/env bash
# setup-steam.sh - provision Steam in Uncork.
#
# We install from Valve's OFFICIAL installer (SteamSetup.exe), downloaded from
# Valve's own CDN onto this Mac and run inside the bottle. We do this rather than
# hosting a pre-built Steam client, because redistributing Valve's client binaries
# is not permitted by the Steam Subscriber Agreement: the client must come from
# Valve to the user. The download uses the Mac's native networking, then the
# installer runs under Wine; on first launch Steam self-updates to the current
# client and shows a login window.
#
# OPTIONAL pre-built snapshot (dev/offline only, NOT hosted by us): if a snapshot
# directory is already on disk (STEAM_CLIENT_SNAPSHOT or the per-user engine dir),
# or a developer points STEAM_CLIENT_SNAPSHOT_URL at their OWN hosting, we clone
# that instead of running the installer. There is no default snapshot URL: Uncork
# never distributes Valve's client.
#
# Known risk: Steam's in-Wine self-update has historically been flaky on the CDN
# fetch ("http error 0"), which is a Wine networking/certificate issue on our side,
# tracked as a Wine fix (see wine-fixes/), not a reason to rehost Valve's binaries.
#
# Emits @@STEP@@ <pct> <msg> progress. Idempotent.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"   # store_prereqs, gptk_baseline_verbs
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"       # ensure_gptk_baseline

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

STEAM_ROOT="$BOTTLE/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_ROOT/steam.exe"
INSTALLED_MARKER="$STEAM_ROOT/package/steam_client_win64.installed"

# Valve's official installer. The client is fetched from Valve's own CDN, never
# from us. Overridable only for mirrors/testing.
STEAM_SETUP_URL="${STEAM_SETUP_URL:-https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe}"

# Optional pre-built client snapshot (dev/offline). Look for one already on disk
# (per-user engine dir, or STEAM_CLIENT_SNAPSHOT). There is deliberately NO default
# snapshot URL: we do not host or redistribute Valve's client. A developer may set
# STEAM_CLIENT_SNAPSHOT_URL to their OWN hosting to opt in.
SNAPSHOT_USER_DIR="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/engine/steam-client-snapshot"
SNAPSHOT="${STEAM_CLIENT_SNAPSHOT:-$SNAPSHOT_USER_DIR}"
[[ -d "$SNAPSHOT/package" ]] || SNAPSHOT="$ENGINE_DIR/steam-client-snapshot"
STEAM_CLIENT_SNAPSHOT_URL="${STEAM_CLIENT_SNAPSHOT_URL:-}"

step 5 "Checking your Mac…"
require_arm64
require_rosetta
require_wine

step 15 "Preparing the Steam bottle…"
ensure_bottle           # wineboot --init + winemetal bridge; idempotent

# Clone a pre-built client snapshot dir into the bottle (APFS clone -> instant).
install_from_snapshot() {
  step 46 "Installing the Steam client…"
  mkdir -p "$STEAM_ROOT"
  ( cd "$SNAPSHOT" && for item in *; do
      cp -Rc "$item" "$STEAM_ROOT/" 2>/dev/null || cp -R "$item" "$STEAM_ROOT/"
    done )
  step 52 "Verifying the Steam client…"
  for need in "$STEAM_EXE" "$INSTALLED_MARKER"; do
    [[ -e "$need" ]] || die "Steam client snapshot incomplete (missing ${need##*/}). Please retry."
  done
  ok "Steam client provisioned from snapshot."
}

# Install from Valve's official SteamSetup.exe. The installer is downloaded from
# Valve's CDN with the Mac's native networking (Wine's HTTP is unreliable here),
# then run inside the bottle. On first launch Steam self-updates to the current
# client. We do NOT write a BootStrapperInhibitAll steam.cfg on this path: a fresh
# install needs that first self-update to pull the actual client.
install_from_official_installer() {
  local cache setup
  cache="${UNCORK_CACHE:-${TMPDIR:-/tmp}/uncork-cache}"; mkdir -p "$cache"
  setup="$cache/SteamSetup.exe"
  step 20 "Downloading Steam from Valve…"
  preflight_network
  preflight_disk 3
  download_progress "$STEAM_SETUP_URL" "$setup" 20 40 "Downloading Steam from Valve…" \
    || die "Couldn't download Steam from Valve. Check your connection and retry."
  step 42 "Installing the Steam client…"
  # /S = NSIS silent install. The installer may page-fault on its auto-launch
  # after a complete extraction, which is harmless; filter that noise.
  wine_run "$setup" /S 2>&1 | grep -v 'page fault\|clipboard manager\|get_thread_times' || true
  WINEPREFIX="$BOTTLE" "$WINE_HOME/bin/wineserver" -k 2>/dev/null || true
  rm -f "$setup"
  step 50 "Verifying the Steam client…"
  for need in "$STEAM_EXE" "$STEAM_ROOT/bin" "$STEAM_ROOT/public"; do
    [[ -e "$need" ]] || die "Steam install incomplete (missing ${need##*/}). Please retry."
  done
  ok "Steam bootstrapper installed from Valve's official installer."
  # The bootstrapper alone is not a complete client; its in-Wine self-update stalls.
  # Complete it by staging the official packages from Valve's CDN with native
  # networking, then letting Steam's own bootstrapper install them.
  bash "$(dirname "${BASH_SOURCE[0]}")/steam-stage-client.sh" \
    || warn "Couldn't fully complete the client now. Open Steam and use 'Finish Steam setup' on the sign-in screen if the login is blank."
}

# --- Provision the Steam client ---------------------------------------------
if [[ -f "$STEAM_EXE" && ( -f "$INSTALLED_MARKER" || -d "$STEAM_ROOT/bin" ) ]]; then
  ok "Steam client already provisioned."
elif [[ -d "$SNAPSHOT/package" ]]; then
  # A pre-built snapshot is already on disk (dev/offline). Use it.
  install_from_snapshot
elif [[ -n "$STEAM_CLIENT_SNAPSHOT_URL" ]]; then
  # A developer opted into their OWN hosted snapshot. Fetch, unpack, then clone.
  step 20 "Downloading a Steam client snapshot…"
  preflight_network
  preflight_disk 3
  mkdir -p "$SNAPSHOT_USER_DIR"
  parent="$(dirname "$SNAPSHOT_USER_DIR")"; tb="$parent/steam-client-snapshot.tar.gz"
  download_progress "$STEAM_CLIENT_SNAPSHOT_URL" "$tb" 20 42 "Downloading a Steam client snapshot…" \
    || die "Couldn't download the snapshot from STEAM_CLIENT_SNAPSHOT_URL."
  step 44 "Unpacking the Steam client…"
  ( cd "$parent" && tar -xf "$tb" ) || die "Couldn't unpack the Steam client snapshot."
  rm -f "$tb"; SNAPSHOT="$SNAPSHOT_USER_DIR"
  install_from_snapshot
else
  # Default: install from Valve's official installer.
  install_from_official_installer
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
