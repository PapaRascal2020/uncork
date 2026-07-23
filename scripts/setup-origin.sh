#!/usr/bin/env bash
# setup-origin.sh - install EA's legacy Origin client into its Wine bottle.
#
# Origin is EA's pre-2022 monolithic client (no EABackgroundService / no localhost
# gRPC, the wall that blocks the modern EA app under Wine; see origin.sh header).
# The thin installer is fetched on demand from EA's CDN (keeps the app lean +
# portable) and run silently, mirroring setup-ubisoft.sh.
#
# NOTE: EA is deprecating Origin; the download URL may eventually redirect to the
# EA app installer. If the fetch stops yielding OriginThinSetup.exe, pin a known
# build via ORIGIN_INSTALLER_URL.
#
# Usage: setup-origin.sh   (invoked by SetupRunner after ensure-engine.sh)

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

INSTALLER_URL="${ORIGIN_INSTALLER_URL:-https://origin-a.akamaihd.net/Origin-Client-Download/production/latest/OriginThinSetup.exe}"
CACHE="${UNCORK_CACHE:-${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/cache}"
INSTALLER="$CACHE/OriginThinSetup.exe"
BOTTLE_NAME="${ORIGIN_BOTTLE:-origin}"
PFX="$BOTTLES_DIR/$BOTTLE_NAME"
WINE="$WINE_HOME/bin/wine"
WINESERVER="$WINE_HOME/bin/wineserver"
ORIGIN_EXE="$PFX/drive_c/Program Files (x86)/Origin/Origin.exe"

export WINEPREFIX="$PFX" WINEARCH=win64 WINEDEBUG="${WINEDEBUG:--all}" MVK_CONFIG_LOG_LEVEL=0
export WINEDLLOVERRIDES="mscoree=n;mshtml="
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

step 5 "Checking your Mac…"
require_arm64; require_rosetta

if [[ -f "$ORIGIN_EXE" ]]; then
  step 90 "Origin is already installed."
else
  step 15 "Downloading Origin…"
  mkdir -p "$CACHE"
  if [[ ! -s "$INSTALLER" ]]; then
    curl -sL "$INSTALLER_URL" -o "$INSTALLER.part" &
    CURL=$!
    total=$(curl -sIL "$INSTALLER_URL" | awk 'tolower($0) ~ /content-length/ {print $2}' | tr -d '\r' | tail -1)
    while kill -0 "$CURL" 2>/dev/null; do
      if [[ -n "$total" && "$total" -gt 0 && -f "$INSTALLER.part" ]]; then
        have=$(stat -f%z "$INSTALLER.part" 2>/dev/null || echo 0)
        pct=$(( 15 + have * 40 / total ))   # download spans 15→55%
        step "$pct" "Downloading Origin… $(( have/1048576 ))/$(( total/1048576 )) MB"
      fi
      sleep 2
    done
    wait "$CURL" || die "Download failed (EA may have retired the Origin installer - set ORIGIN_INSTALLER_URL)."
    mv "$INSTALLER.part" "$INSTALLER"
  fi
  # sanity: EA's CDN sometimes serves the EA-app installer under this path now.
  if ! file "$INSTALLER" 2>/dev/null | grep -qi "executable\|PE32"; then
    die "Downloaded file isn't a Windows installer - EA likely redirected to the EA app. Pin ORIGIN_INSTALLER_URL to a real OriginThinSetup.exe."
  fi

  step 58 "Preparing the bottle…"
  if [[ ! -e "$PFX/system.reg" ]]; then
    "$WINE" wineboot --init >/dev/null 2>&1 || true
    "$WINESERVER" -w 2>/dev/null || true
  fi
  "$WINE" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentVersion /t REG_SZ /d 10.0 /f >/dev/null 2>&1 || true

  step 70 "Installing Origin…"
  cp "$INSTALLER" "$PFX/drive_c/OriginSetup.exe"
  "$WINE" 'C:\OriginSetup.exe' /SILENT >/dev/null 2>&1 &
  ip=$!; t=0
  while kill -0 "$ip" 2>/dev/null; do [[ "$t" -ge 300 ]] && break; sleep 4; t=$((t+4)); done
  for p in OriginSetup OriginThinSetup Origin.exe OriginWebHelperService OriginClientService; do pkill -f "$p" 2>/dev/null || true; done
  "$WINESERVER" -k 2>/dev/null || true
fi

step 85 "Turning off Origin's in-game overlay + auto-update churn…"
# EACore.ini: disable IGO (crashes under Wine) + client self-update (keeps the
# pinned, working build). Lives next to Origin.exe. Best-effort.
ORIGIN_DIR="$PFX/drive_c/Program Files (x86)/Origin"
if [[ -d "$ORIGIN_DIR" ]]; then
  cat > "$ORIGIN_DIR/EACore.ini" <<'INI'
[connection]
EnableIGOProxy=false
[Feature]
EnableIGO=false
[Bootstrap]
EnableUpdating=false
INI
fi

step 92 "Preparing the graphics environment…"
if gptk_available; then ensure_gptk_prefix "$BOTTLE_NAME" || true; fi

if [[ -f "$ORIGIN_EXE" ]]; then
  step 100 "Origin is installed."
  ok "Origin installed."
else
  step 100 "Setup finished with warnings."
  die "Origin didn't install (no Origin.exe under $PFX)."
fi
