#!/usr/bin/env bash
# ensure-cli.sh - provision a bundled runtime on demand into the writable per-user
# engine dir, so a source clone (which ships no engine/) still yields a working
# app. No-op if the component is already present (bundled in the payload or already
# fetched). DXVK comes from the upstream release; the Epic/GOG clients are pure
# Python and are installed with the system python3.
#
# Usage: ensure-cli.sh <dxvk|legendary|gogdl>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

ID="${1:?usage: ensure-cli.sh <dxvk|legendary|gogdl>}"
DATA_ENGINE="$UNCORK_DATA_DIR/engine"
CACHE="${UNCORK_CACHE:-$UNCORK_DATA_DIR/cache}"
PY="/usr/bin/python3"                  # the CLT python the venvs are built against
mkdir -p "$DATA_ENGINE" "$CACHE"

need_python() { [[ -x "$PY" ]] || die "Python 3 not found. Install the Xcode Command Line Tools: xcode-select --install"; }

case "$ID" in
  dxvk)
    [[ -d "$ENGINE_DIR/dxvk/x64" || -d "$DATA_ENGINE/dxvk/x64" ]] && { ok "DXVK already present."; exit 0; }
    URL="${DXVK_URL:-https://github.com/doitsujin/dxvk/releases/download/v3.0.2/dxvk-3.0.2.tar.gz}"
    step 10 "Downloading DXVK…"
    tb="$CACHE/dxvk.tar.gz"; tmp="$(mktemp -d)"
    curl -fsSL "$URL" -o "$tb" || die "Couldn't download DXVK from $URL"
    tar -xzf "$tb" -C "$tmp" || die "DXVK extract failed."
    x64="$(find "$tmp" -type d -name x64 | head -1)"
    x32="$(find "$tmp" -type d -name x32 | head -1)"
    [[ -d "$x64" ]] || die "DXVK archive had no x64/ directory."
    rm -rf "$DATA_ENGINE/dxvk"; mkdir -p "$DATA_ENGINE/dxvk"
    cp -R "$x64" "$DATA_ENGINE/dxvk/x64"
    [[ -d "$x32" ]] && cp -R "$x32" "$DATA_ENGINE/dxvk/x32"
    rm -rf "$tmp" "$tb"
    step 100 "DXVK ready."; ok "Installed DXVK into engine/dxvk (per-user)." ;;

  legendary)
    [[ -x "$ENGINE_DIR/legendary-venv/bin/legendary" || -x "$DATA_ENGINE/legendary-venv/bin/legendary" ]] && { ok "legendary already present."; exit 0; }
    need_python
    step 10 "Setting up the Epic client (legendary)…"
    dest="$DATA_ENGINE/legendary-venv"; rm -rf "$dest"
    "$PY" -m venv "$dest" || die "Couldn't create a Python environment for legendary."
    step 50 "Installing legendary…"
    "$dest/bin/pip" install --quiet --disable-pip-version-check legendary-gl || die "Installing legendary-gl failed (network?)."
    [[ -x "$dest/bin/legendary" ]] || die "legendary console script missing after install."
    step 100 "Epic client ready."; ok "Installed legendary into engine/legendary-venv (per-user)." ;;

  gogdl)
    [[ -x "$ENGINE_DIR/gogdl-venv/bin/gogdl" || -x "$DATA_ENGINE/gogdl-venv/bin/gogdl" ]] && { ok "gogdl already present."; exit 0; }
    need_python
    command -v git >/dev/null || die "git not found (needed to install gogdl). Install the Xcode Command Line Tools."
    step 10 "Setting up the GOG client (gogdl)…"
    dest="$DATA_ENGINE/gogdl-venv"; rm -rf "$dest"
    "$PY" -m venv "$dest" || die "Couldn't create a Python environment for gogdl."
    step 50 "Installing gogdl…"
    "$dest/bin/pip" install --quiet --disable-pip-version-check "git+https://github.com/Heroic-Games-Launcher/heroic-gogdl.git" \
      || die "Installing gogdl failed (network?)."
    [[ -x "$dest/bin/gogdl" ]] || die "gogdl console script missing after install."
    step 100 "GOG client ready."; ok "Installed gogdl into engine/gogdl-venv (per-user)." ;;

  *) die "Unknown component '$ID' (expected dxvk, legendary, or gogdl)." ;;
esac
