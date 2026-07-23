#!/usr/bin/env bash
# run.sh - build + run the gRPC-over-Wine localhost diagnostics.
# Proves whether Wine's winsock/IOCP + resolver satisfy what gRPC needs for a
# local channel. See README.md for the findings.
#
# Env overrides:
#   WINE      full path to a wine binary (default: our CrossOver-26 build)
#   WINEPREFIX a bottle to run in (default: a throwaway prefix)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

MINGW="${MINGW:-x86_64-w64-mingw32-gcc}"
command -v "$MINGW" >/dev/null || { echo "need $MINGW (brew install mingw-w64)"; exit 1; }

WINE="${WINE:-$HOME/wine-cx-build/cx26-root/usr/local/bin/wine}"
[[ -x "$WINE" ]] || { echo "no wine at $WINE (set WINE=...)"; exit 1; }
export WINEPREFIX="${WINEPREFIX:-$HERE/.wp}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=n;mshtml=}"
export WINEDEBUG="${WINEDEBUG:--all}"
export DYLD_FALLBACK_LIBRARY_PATH="${DYLD_FALLBACK_LIBRARY_PATH:-$ROOT/engine/wine-stable/lib:/usr/lib}"

echo "==> booting prefix $WINEPREFIX"
"$WINE" wineboot -u >/dev/null 2>&1 || true

for src in "$HERE"/0*.c; do
  exe="${src%.c}.exe"
  echo; echo "==> $(basename "$src")"
  "$MINGW" -O2 -o "$exe" "$src" -lws2_32 -lmswsock
  "$WINE" "$exe" 2>/dev/null || true
done
