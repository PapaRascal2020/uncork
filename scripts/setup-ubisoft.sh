#!/usr/bin/env bash
# setup-ubisoft.sh - install the Ubisoft Connect client into its Wine bottle.
# The client is downloaded on demand from Ubisoft's CDN (keeps the app lean and
# is portable, every Mac fetches the current installer) then installed silently.
#
# NOTE: Ubisoft Connect is Chromium/CEF (UplayWebCore.exe), same class as the EA
# app. Pass 1 goal is that it INSTALLS; getting its CEF UI to render is the same
# follow-up as EA (shared fix).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

INSTALLER_URL="https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe"
CACHE="${UNCORK_CACHE:-${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/cache}"
INSTALLER="$CACHE/UbisoftConnectInstaller.exe"
BOTTLE_NAME="ubisoft"
PFX="$BOTTLES_DIR/$BOTTLE_NAME"
WINE="$WINE_HOME/bin/wine"
WINESERVER="$WINE_HOME/bin/wineserver"
LAUNCHER_EXE="$PFX/drive_c/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe"

export WINEPREFIX="$PFX" WINEARCH=win64 WINEDEBUG="${WINEDEBUG:--all}" MVK_CONFIG_LOG_LEVEL=0
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

step 5 "Checking your Mac…"
require_arm64; require_rosetta

# Already installed? Skip straight to prep.
if [[ -f "$LAUNCHER_EXE" ]]; then
  step 90 "Ubisoft Connect is already installed."
else
  step 15 "Downloading Ubisoft Connect (~265 MB)…"
  mkdir -p "$CACHE"
  # Fetch with a byte-progress poller so the UI shows real download progress.
  if [[ ! -s "$INSTALLER" ]]; then
    curl -sL "$INSTALLER_URL" -o "$INSTALLER.part" &
    CURL=$!
    total=$(curl -sIL "$INSTALLER_URL" | awk 'tolower($0) ~ /content-length/ {print $2}' | tr -d '\r' | tail -1)
    while kill -0 "$CURL" 2>/dev/null; do
      if [[ -n "$total" && "$total" -gt 0 && -f "$INSTALLER.part" ]]; then
        have=$(stat -f%z "$INSTALLER.part" 2>/dev/null || echo 0)
        pct=$(( 15 + have * 45 / total ))     # download spans 15→60%
        step "$pct" "Downloading Ubisoft Connect… $(( have/1048576 ))/$(( total/1048576 )) MB"
      fi
      sleep 2
    done
    wait "$CURL" || die "Download failed."
    mv "$INSTALLER.part" "$INSTALLER"
  fi
  step 60 "Preparing the bottle…"
  if [[ ! -e "$PFX/system.reg" ]]; then
    "$WINE" wineboot --init >/dev/null 2>&1 || true
    "$WINESERVER" -w 2>/dev/null || true
  fi
  "$WINE" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentVersion /t REG_SZ /d 10.0 /f >/dev/null 2>&1 || true

  step 70 "Installing Ubisoft Connect…"
  cp "$INSTALLER" "$PFX/drive_c/UbiInstaller.exe"
  # NSIS silent install. Run with a wall-clock guard; the installer may auto-spawn
  # the client, which we stop afterward (Pass 1 = installed, not launched).
  "$WINE" 'C:\UbiInstaller.exe' /S >/dev/null 2>&1 &
  ip=$!; t=0
  while kill -0 "$ip" 2>/dev/null; do [[ "$t" -ge 300 ]] && break; sleep 4; t=$((t+4)); done
  # stop the installer + any auto-launched client
  for p in UbiInstaller UbisoftConnect upc UplayWebCore UbisoftGameLauncher UplayService; do pkill -f "$p" 2>/dev/null || true; done
  "$WINESERVER" -k 2>/dev/null || true
fi

step 92 "Preparing the graphics environment…"
if gptk_available; then ensure_gptk_prefix ubisoft || true; fi

if [[ -f "$LAUNCHER_EXE" ]]; then
  step 100 "Ubisoft Connect is installed."
  ok "Ubisoft Connect installed."
else
  step 100 "Setup finished with warnings."
  die "Ubisoft Connect didn't install (no UbisoftConnect.exe)."
fi
