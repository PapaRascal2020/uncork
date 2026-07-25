#!/usr/bin/env bash
# ensure-python.sh - fetch a relocatable Python on demand, so Uncork does not
# depend on the Xcode Command Line Tools. The Epic (legendary) and GOG (gogdl)
# clients are pure Python and run against this interpreter with PYTHONPATH pointed
# at their bundled site-packages; our small JSON helpers use it too.
#
# We use astral-sh/python-build-standalone "install_only" builds, which extract to
# a self-contained python/ tree (bin/python3, lib/...). Pinned to a 3.11 build:
# 3.11 still ships distutils, so even older bundled client versions keep working,
# and it runs the pure-Python site-packages regardless of their 3.9 path.
#
# Idempotent: no-ops if a usable interpreter is already present. Emits @@STEP@@.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

PY_URL="${UNCORK_PYTHON_URL:-https://github.com/astral-sh/python-build-standalone/releases/download/20260718/cpython-3.11.15+20260718-aarch64-apple-darwin-install_only.tar.gz}"
DEST="$UNCORK_DATA_DIR/engine"          # archive has a top-level python/ dir
PY_BIN="$DEST/python/bin/python3"
CACHE="${UNCORK_CACHE:-${TMPDIR:-/tmp}/uncork-cache}"

# Already provisioned (bundled payload or a previous fetch)?
if _resolve_python >/dev/null 2>&1; then
  ok "Python already available."; exit 0
fi

require_arm64
preflight_network
mkdir -p "$DEST" "$CACHE"
tb="$CACHE/python-standalone.tar.gz"

step 10 "Downloading Python (first run)…"
download_progress "$PY_URL" "$tb" 10 80 "Downloading Python…" \
  || die "Couldn't download Python from $PY_URL. Check your connection and retry."

step 85 "Extracting Python…"
rm -rf "$DEST/python"
tar -xf "$tb" -C "$DEST" || die "Couldn't extract Python."
rm -f "$tb"
[[ -x "$PY_BIN" ]] || die "Extracted, but $PY_BIN is missing."

# Sanity check the interpreter actually runs (Rosetta not involved; this is arm64).
"$PY_BIN" -c 'import json,sys' 2>/dev/null || die "Fetched Python did not run cleanly."

step 100 "Python ready."
ok "Python provisioned: $PY_BIN"
