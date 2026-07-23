#!/usr/bin/env bash
# ea.sh: launch the EA app (EA Desktop) in Uncork.
#
# The EA app is a Qt + embedded-Chromium (CEF) desktop client. Three things are
# needed to run it under Wine on Apple Silicon:
#   1. It's a 2D app, no D3DMetal needed; DXVK (via MoltenVK) gives it a working
#      D3D11 device. So it runs on our bundled Wine 11 (newer than GPTk).
#   2. It's installed by EXTRACTING the MSI file tree (msiexec /a), not by running
#      the installer: the MSI's WiX *managed* custom actions can't run under Wine
#      (SFXCA host fails). So real .NET 4.8 in the prefix + /a extract sidesteps them.
#   3. EADesktop.exe connects to its "Background Service" (BGS) over IPC and QUITS
#      if it can't. The service must be REGISTERED IN WINE'S SCM (sc create) and
#      STARTED (sc start) *before* the app; a bare process isn't found. Do it all
#      in one wineserver session so services.exe stays live when the app queries.
#
# Usage: ea.sh launch (default) | stop

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOTTLE_NAME="${BOTTLE_NAME:-ea-app}"   # override to test on a wine-cef bottle (e.g. ea-cef)
PFX="$BOTTLES_DIR/$BOTTLE_NAME"
WINE="$WINE_HOME/bin/wine"
WINESERVER="$WINE_HOME/bin/wineserver"
SVC="EABackgroundService"

export WINEPREFIX="$PFX"
export WINEDEBUG="${WINEDEBUG:--all}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
# EA's OpenSSL (login/TLS + the BGS crypto) misdetects CPU features under
# emulation (Rosetta), which crashes the handshake; the documented Proton EA-app
# fix is to mask them off. This is the likely cause of the BGS/login IPC failing.
export OPENSSL_ia32cap="${OPENSSL_ia32cap:-~0x20000000}"
# EADesktop<->EABackgroundService talk over a local gRPC channel to "localhost:<port>".
# That channel gets stuck in CONNECTING at "started resolving" and EA logs
# "stub invalid" forever, no window. This is NOT a Wine bug we can fix here: isolated
# reproducers show Wine's winsock/IOCP transport AND every resolver path (getaddrinfo,
# c-ares getaddrinfo/raw-query, GetAddrInfoExW sync+async, overlapped UDP recv via IOCP)
# all work under this Wine bottle. The hang is internal to gRPC's own EventEngine/resolver
# orchestration compiled into EADesktop.exe. Full write-up + tests:
# wine-fixes/diagnostics/grpc-localhost/. GRPC_DNS_RESOLVER below had no effect. The
# viable EA path is Origin (pre-2022 client, no BGS/gRPC), not the EA app.
export GRPC_DNS_RESOLVER="${GRPC_DNS_RESOLVER:-native}"

stop_ea() {
  for p in EADesktop EACefSubProcess "$SVC" EALocalHostSvc EAConnect Link2EA IGOProxy; do
    pkill -f "$p" 2>/dev/null || true
  done
  WINEPREFIX="$PFX" "$WINESERVER" -k 2>/dev/null || true
}

case "${1:-launch}" in
  stop) stop_ea; ok "EA app stopped."; exit 0 ;;
  launch) : ;;
  *) die "usage: ea.sh [launch|stop]" ;;
esac

# Locate the installed EA Desktop app dir (holds EADesktop.exe + EABackgroundService.exe).
SVC_UNIX="$(find "$PFX/drive_c" -iname EABackgroundService.exe 2>/dev/null | head -1)"
APPDIR="$(dirname "$SVC_UNIX")"
[[ -n "$APPDIR" && -f "$APPDIR/EADesktop.exe" ]] || die "EA app isn't installed (no EADesktop.exe under $PFX)."

# Windows path to the service exe: strip <prefix>/drive_c, C:-prefix, / -> backslash.
win_path() { local p="${1#$PFX/drive_c}"; printf 'C:%s' "${p//\//\\}"; }
SVC_WIN="$(win_path "$SVC_UNIX")"

# Reset to a clean session first. Wine's SCM keeps service state in the running
# services.exe; if a previous BGS process was killed, SCM can be left thinking the
# service is still "running" (stale), so `sc start` becomes a no-op and the app
# connects to a dead BGS and quits. Killing wineserver clears that in-memory state;
# on the next boot services.exe reads the registry fresh (service = STOPPED).
stop_ea; sleep 1
WINEPREFIX="$PFX" "$WINESERVER" -p 2>/dev/null || true

# Register the Background Service in Wine's SCM. Use `start= demand` (NOT auto):
# with auto, services.exe auto-starts BGS on boot AND our sc start hits it, which
# can spin up two instances / restart it onto a different port, so the port we
# read wouldn't match the live one. Demand = only WE start it, exactly once, one
# deterministic port. `|| true` throughout: sc returns non-zero for benign states
# (e.g. 1056 already-running) and the script runs under `set -e`.
bgs_up() { pgrep -f 'EABackgroundService.exe' >/dev/null 2>&1; }
if ! "$WINE" sc query "$SVC" 2>/dev/null | grep -qi "SERVICE_NAME"; then
  log "Registering EA background service…"
  "$WINE" sc create "$SVC" binPath= "\"$SVC_WIN\" -servicename=$SVC -noupnp" start= auto >/dev/null 2>&1 || true
fi

# CRITICAL: EA's dynamic BGS-port discovery fails under Wine (the app connects to a
# gRPC server BGS opens on a random localhost port; discovery returns "stub invalid"
# and the CEF login window never appears). BGS logs the port it's listening on:
# read THIS start's port and pass it via -ipcport, bypassing discovery. Then the app
# connects, creates its CEF browser, and loads the login page.
# Mark the log position BEFORE starting so we only read the port from THIS boot,
# never a stale one from a previous run (the log accumulates across runs).
BGSLOG="$PFX/drive_c/ProgramData/EA Desktop/Logs/EABackgroundServiceVerbose.log"
mark=0; [[ -f "$BGSLOG" ]] && mark=$(wc -l < "$BGSLOG" 2>/dev/null | tr -d ' ')

# Start BGS ONCE. `stop_ea` above already killed any prior BGS + wineserver, so this
# boot creates a single fresh instance, do NOT re-issue sc start in a loop (it can
# restart BGS onto a new port). `|| true`: sc returns non-zero for benign states.
log "Starting EA background service…"
"$WINE" sc start "$SVC" >/dev/null 2>&1 || true

IPCPORT=""
# BGS cold-boots under Wine; the "Ipc Server listening" line can take 30-40s to
# appear. A 20-iteration wait timed out and EADesktop launched portless (→ quit),
# so wait up to 60s. We killed any prior BGS above, so the newest port line after
# `mark` is unambiguously THIS run's.
for _ in $(seq 1 60); do
  if bgs_up && [[ -f "$BGSLOG" ]]; then
    # `|| true`: under `set -euo pipefail`, a no-match grep here returns non-zero and
    # the assignment would ABORT the whole script mid-loop (before EADesktop ever
    # launches). Swallow it so the loop retries until BGS logs its port.
    IPCPORT="$(tail -n "+$((mark+1))" "$BGSLOG" 2>/dev/null | grep -aE 'Ipc Server listening' | tail -1 | grep -oE 'port \[[0-9]+\]' | grep -oE '[0-9]+' || true)"
    [[ -n "$IPCPORT" ]] && break
  fi
  sleep 1
done
[[ -n "$IPCPORT" ]] || warn "Background service didn't report a port cleanly."

# Wait until BGS is actually ACCEPTING TCP on that port: "listening" is logged
# early, but the gRPC server needs a moment more to accept. Launching before it's
# ready is the race that makes the login window flaky ("stub invalid"). A real
# connect probe (bash /dev/tcp) is deterministic where a fixed sleep isn't.
if [[ -n "$IPCPORT" ]]; then
  log "Waiting for the service to accept connections…"
  ready=""
  for _ in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$IPCPORT") 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; ready=1; break; fi
    sleep 1
  done
  [[ -n "$ready" ]] || warn "Service port $IPCPORT not accepting yet; launching anyway."
  sleep 2   # small settle after it starts accepting
fi
[[ -n "$IPCPORT" ]] && log "BGS IPC port $IPCPORT" || warn "Couldn't read BGS IPC port; launching without it (UI may not appear)."

log "Launching EA app…"
cd "$APPDIR"
# Launch DETACHED (nohup + disown) so the EA app keeps running in the user's
# desktop session after this command returns: an exec'd foreground app gets torn
# down when the invoking shell exits, so its window never persists. Runtime output
# is captured for diagnostics.
RUNLOG="${UNCORK_CACHE:-${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}/cache}/ea-runtime.log"
mkdir -p "$(dirname "$RUNLOG")"
# EADesktop embeds Chromium/CEF (like Ubisoft Connect). Pass the SAME CEF flags
# Ubisoft needs under Wine: --no-sandbox (Chromium's sandbox crashes the renderer
# under Wine) and --disable-direct-composition (Wine's DComp is a stub → use the
# DXGI-swapchain present path). Without these the CEF window fails to appear.
nohup "$WINE" "$APPDIR/EADesktop.exe" ${IPCPORT:+"-ipcport=$IPCPORT"} \
  --no-sandbox --disable-direct-composition >"$RUNLOG" 2>&1 &
disown 2>/dev/null || true
ok "EA app launched - its window should appear in a few seconds. (log: $RUNLOG)"
