#!/usr/bin/env bash
# package-app.sh - Build Uncork and assemble a proper macOS .app bundle, so it's
# double-clickable, shows the wine-bottle icon, and reads "Uncork" everywhere
# (menu bar, Dock, About-this-Mac) via CFBundleName.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Uncork.app"

# Quit any RUNNING instance of this app first. Repackaging over a live bundle
# corrupts its code signature ("code has no resources"). Scoped to THIS bundle's
# own binary path (a unique, specific match), never a broad name kill.
if pgrep -f "$APP/Contents/MacOS/Uncork" >/dev/null 2>&1; then
  echo "==> Quitting the running Uncork before repackaging"
  osascript -e 'tell application "Uncork" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -f "$APP/Contents/MacOS/Uncork" 2>/dev/null || true
  sleep 1
fi

echo "==> Building release binary"
( cd "$ROOT/app" && swift build -c release 2>&1 | tail -3 )

echo "==> Assembling $APP"
# A previous signed bundle carries macOS App-Management protection + read-only venv
# files, which make rm/cp/chmod fail "Operation not permitted" and leave the new
# bundle with an INVALID signature. Clear protection + make writable before removing.
if [[ -d "$APP" ]]; then
  xattr -cr "$APP" 2>/dev/null || true
  chmod -R u+w "$APP" 2>/dev/null || true
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/app/.build/release/Uncork" "$APP/Contents/MacOS/Uncork"
# App icon is tracked in assets/. Non-fatal: a missing icon just yields the default.
if [[ -f "$ROOT/assets/Uncork.icns" ]]; then
  cp "$ROOT/assets/Uncork.icns" "$APP/Contents/Resources/Uncork.icns"
else
  echo "    (no assets/Uncork.icns; app will use the default icon)"
fi

# --- Bundle the read-only payload so the app runs on ANY Mac -----------------
# Paths.swift looks for this at Contents/Resources/uncork. Everything writable
# (bottles, legendary config) is created in ~/Library/Application Support/Uncork
# at runtime, so nothing here is ever mutated: the bundle stays read-only-safe.
PAYLOAD="$APP/Contents/Resources/uncork"
echo "==> Bundling payload → ${PAYLOAD#"$ROOT/"}"
mkdir -p "$PAYLOAD/engine"
cp -R "$ROOT/scripts" "$PAYLOAD/scripts"
cp -R "$ROOT/tools"   "$PAYLOAD/tools"
cp -R "$ROOT/compat"  "$PAYLOAD/compat"
# wine-fixes catalogs (engines.json, wine-builds.json) + scripts read them at runtime
# (Wine Manager, ensure-wine-build.sh). Small: JSON + patch text, no binaries.
cp -R "$ROOT/wine-fixes" "$PAYLOAD/wine-fixes"
cp -R "$ROOT/docs"    "$PAYLOAD/docs"     # in-app Developer Guide reads docs/DEVELOPERS.md
# Engine: only what the app actually runs. Skip source trees, tarballs, build
# logs, and the experimental wine-stable-t (they'd bloat the bundle by ~400 MB).
#   - wine-stable    the Wine engine (DXMT/winemetal is already baked in)
#   - dxvk           legacy DX9 fallback
#   - legendary-venv Epic CLI (note: venv is not yet relocatable, see below)
# UNCORK_SLIM=1 omits the two big Wine engines (~1.8 GB) from the bundle; they are
# then fetched on first use into the writable per-user engine dir by
# ensure-wine-engine.sh (wine-stable from the public Gcenx release; wine-cef from
# WINE_CEF_URL, which must be hosted). Default (unset) bundles them, so the app
# works fully offline out of the box and nothing regresses.
SLIM="${UNCORK_SLIM:-0}"
# Copy an engine component if it exists. A source clone has no engine/ dir (it is
# gitignored), so a missing component is skipped with a note, never fatal. The
# build kit ships these; wine-stable and wine-cef also download on first use.
bundle_engine() { # <name>
  if [[ -d "$ROOT/engine/$1" ]]; then cp -R "$ROOT/engine/$1" "$PAYLOAD/engine/$1"
  else echo "    (engine/$1 not present, skipped)"; fi
}
if [[ "$SLIM" == 1 ]]; then
  echo "    [slim] omitting wine-stable + wine-cef (downloaded on first use)"
else
  bundle_engine wine-stable
  bundle_engine wine-cef
fi
bundle_engine dxvk             # legacy DX fallback
bundle_engine legendary-venv   # Epic CLI (run relocatably; see below)
bundle_engine gogdl-venv       # GOG CLI (gogdl)
# GPTk Wine + D3DMetal (the primary graphics backend) is NOT bundled; the setup
# wizard downloads it on first run (ensure-engine.sh) into a writable per-user dir
# (~/Library/Application Support/Uncork/engine/gptk). Keeps the app lean.
# Drop dev cruft that shouldn't ship inside the payload.
rm -rf "$PAYLOAD/scripts/wrapper" "$PAYLOAD"/*/.DS_Store 2>/dev/null || true
find "$PAYLOAD" -name '.DS_Store' -delete 2>/dev/null || true
# Symlinks that make codesign fail (→ broken signature → BLANK app icon):
#   (a) ABSOLUTE symlinks (e.g. the legendary venv's python3 → an out-of-bundle
#       path). We don't need the venv's own python (epic.sh runs legendary with
#       the system /usr/bin/python3), so dropping it is safe.
#   (b) BROKEN/dangling symlinks (e.g. bin/python → python3 once python3 is gone).
# Order matters: remove absolutes first, which may create danglers, then danglers.
find "$PAYLOAD" -type l -lname '/*' -delete 2>/dev/null || true
find "$PAYLOAD" -type l ! -exec test -e {} \; -delete 2>/dev/null || true
echo "    payload size: $(du -sh "$PAYLOAD" | cut -f1)"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Uncork</string>
    <key>CFBundleDisplayName</key>     <string>Uncork</string>
    <key>CFBundleExecutable</key>      <string>Uncork</string>
    <key>CFBundleIdentifier</key>      <string>com.uncork.app</string>
    <key>CFBundleIconFile</key>        <string>Uncork</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.games</string>
</dict>
</plist>
PLIST

# Strip the com.apple.provenance xattr macOS stamps on freshly-created app
# bundles: it trips "App Management" protection and makes codesign fail with
# "Operation not permitted". Clearing xattrs (best-effort) lets --deep sign.
chmod -R u+w "$APP" 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true

# Codesign. Default is an ad-hoc signature (identity "-"), which is all a developer
# needs for local builds. Set UNCORK_SIGN_ID to sign with a real identity instead
# (e.g. a Developer ID for a release; scripts/release.sh does exactly that and adds
# notarization). We strip absolute symlinks from the payload above, so `--deep`
# succeeds. A FAILED sign leaves a broken signature and macOS shows a BLANK app
# icon, which is exactly the bug this avoids. Report failure instead of hiding it.
SIGN_ID="${UNCORK_SIGN_ID:--}"
[[ "$SIGN_ID" == "-" ]] || echo "==> Signing with identity: $SIGN_ID"
codesign --remove-signature "$APP" >/dev/null 2>&1 || true
codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1 || true
# The first --deep pass can seal inconsistently while nested Python-venv files are
# still settling (bundled gogdl/legendary venvs), leaving "code has no resources"
# invalid. A second chmod+xattr+sign reliably fixes it, so verify and re-sign once.
if ! codesign -v "$APP" >/dev/null 2>&1; then
  chmod -R u+w "$APP" 2>/dev/null || true
  xattr -cr "$APP" 2>/dev/null || true
  codesign --remove-signature "$APP" >/dev/null 2>&1 || true
  codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1 || true
fi
codesign -v "$APP" >/dev/null 2>&1 || echo "!! codesign still invalid - app icon may render blank." >&2

# Refresh LaunchServices + the icon cache so a rebuilt-in-place bundle doesn't
# keep showing a stale/blank icon.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1 || true

echo "==> Done: $APP"
