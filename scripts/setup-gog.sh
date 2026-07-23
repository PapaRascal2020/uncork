#!/usr/bin/env bash
# setup-gog.sh - prepare GOG in Uncork. The graphics engine (Wine + D3DMetal) is
# ensured by the wizard before this runs. GOG is DRM-free and driven by gogdl
# (bundled), so setup just readies the shared "gog" D3DMetal bottle; you
# then signs in once with a browser code (like Epic).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"   # gptk_baseline_verbs

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

step 10 "Checking your Mac…"
require_arm64
require_rosetta

step 40 "Checking the GOG downloader…"
GOG_SCRIPT="$ENGINE_DIR/gogdl-venv/bin/gogdl"
GOG_SP="$ENGINE_DIR/gogdl-venv/lib/python3.9/site-packages"
if [[ -f "$GOG_SCRIPT" && -d "$GOG_SP" ]]; then
  ok "GOG downloader (gogdl) is ready."
else
  warn "gogdl not bundled - GOG library actions will be unavailable until it's installed."
fi

step 50 "Preparing the GOG environment (D3DMetal)…"
if gptk_available; then
  ensure_gptk_prefix gog || warn "Couldn't fully prepare the D3DMetal prefix (will retry on first launch)."
  ensure_gptk_baseline gog   # baseline libraries (emits @@STEP@@ 70→95)
else
  warn "Graphics engine not found - the wizard should have installed it first."
fi

step 100 "GOG is ready - sign in next."
ok "GOG prepared."
