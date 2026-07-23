#!/usr/bin/env bash
# setup-ea.sh - prepare the EA app in Uncork. The graphics engine (Wine +
# D3DMetal) is ensured by the wizard before this runs; here we ready EA's
# D3DMetal prefix.
#
# NOTE: installing the real EA app (Chromium/CEF, like Steam's client) is the
# experimental follow-up, same class as the Steam client, so it'll likely need
# a provisioned snapshot rather than the EA installer's own self-update.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

step 10 "Checking your Mac…"
require_arm64
require_rosetta

step 45 "Preparing the EA environment (D3DMetal)…"
if gptk_available; then
  ensure_gptk_prefix ea || warn "Couldn't fully prepare the D3DMetal prefix (will retry on first launch)."
else
  warn "Graphics engine not found - the wizard should have installed it first."
fi

step 100 "EA is ready."
ok "EA prepared."
