#!/usr/bin/env bash
# setup-epic.sh - prepare Epic in Uncork. The graphics engine (Wine + D3DMetal)
# is already ensured by the wizard before this runs. This readies the Epic
# D3DMetal prefix so games launch on D3DMetal.
#
# NOTE: installing the *real* Epic Games Launcher GUI (EpicInstaller.msi, CEF) is
# the experimental follow-up; for now Epic is driven via Uncork's built-in
# library (legendary) which already launches games on D3DMetal.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gptk.sh"
source "$(dirname "${BASH_SOURCE[0]}")/compatdb.sh"   # gptk_baseline_verbs

step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

step 10 "Checking your Mac…"
require_arm64
require_rosetta

step 45 "Preparing the Epic environment (D3DMetal)…"
if gptk_available; then
  ensure_gptk_prefix epic || warn "Couldn't fully prepare the D3DMetal prefix (will retry on first launch)."
  # Baseline libraries so most Epic games run with no per-game config (emits its
  # own @@STEP@@ 70→95 progress).
  ensure_gptk_baseline epic
else
  warn "Graphics engine not found - the wizard should have installed it first."
fi

step 100 "Epic is ready - sign in next."
ok "Epic prepared."
