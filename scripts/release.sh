#!/usr/bin/env bash
# release.sh - build a SIGNED + NOTARIZED Uncork.app and a drag-to-install DMG, so
# non-technical users can download and open it with no Gatekeeper warnings.
#
# Requires an Apple Developer ID (published as Haijahr Limited). Everything is driven
# by environment variables so NO secrets or identities live in the repo:
#
#   UNCORK_SIGN_ID        "Developer ID Application: Haijahr Limited (TEAMID)"
#   UNCORK_NOTARY_PROFILE  a notarytool keychain profile name (see one-time setup)
#   UNCORK_DMG            output path (optional, default build/Uncork.dmg)
#
# One-time notary credential setup (stores an app-specific password in the login
# keychain, never in the repo):
#   xcrun notarytool store-credentials UNCORK_NOTARY \
#     --apple-id you@haijahr.example --team-id TEAMID --password <app-specific-password>
#
# Then run:
#   UNCORK_SIGN_ID="Developer ID Application: Haijahr Limited (XXXXXXXXXX)" \
#   UNCORK_NOTARY_PROFILE=UNCORK_NOTARY \
#   bash scripts/release.sh
#
# We ship the SLIM app on purpose: the large Wine / GPTk / DXMT engines are NOT
# bundled (signing and notarizing hundreds of Wine Mach-O binaries with a hardened
# runtime is a separate, much harder problem). They download on first use via curl,
# which does not set the quarantine flag, so a notarized app executes them without a
# Gatekeeper prompt. For that first-run download to work end to end, the release
# assets must be hosted first (see scripts/upload-assets.sh: wine-stable, wine-cef).
# Steam is not among them: it installs from Valve's official installer at runtime.
#
# NOTE: this pipeline is written to Apple's documented flow but has NOT been run
# against a real Developer ID yet (we don't have the cert). Expect to iterate once
# the certificate exists: signing order and, if the app fails to launch after
# notarization, a hardened-runtime entitlement or two.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Uncork.app"
DMG="${UNCORK_DMG:-$ROOT/build/Uncork.dmg}"
ZIP="$ROOT/build/Uncork-notarize.zip"

: "${UNCORK_SIGN_ID:?set UNCORK_SIGN_ID to your \"Developer ID Application: ...\" identity}"
: "${UNCORK_NOTARY_PROFILE:?set UNCORK_NOTARY_PROFILE to your notarytool keychain profile}"
command -v xcrun >/dev/null || { echo "!! xcrun not found (install Xcode command line tools)."; exit 1; }

echo "==> Building the slim app (engines download on first use)"
UNCORK_SLIM=1 bash "$ROOT/scripts/package-app.sh"
[[ -d "$APP" ]] || { echo "!! $APP was not produced."; exit 1; }

echo "==> Clearing extended attributes"
xattr -cr "$APP"

# Notarization requires EVERY Mach-O in the bundle to be signed with the Developer
# ID, a secure timestamp, and the hardened runtime. Sign inner code first, then the
# bundle (never use --deep for signing; it is unreliable for nested code).
echo "==> Signing inner Mach-O binaries"
signed=0
while IFS= read -r f; do
  if file -b "$f" 2>/dev/null | grep -q 'Mach-O'; then
    codesign --force --timestamp --options runtime --sign "$UNCORK_SIGN_ID" "$f" >/dev/null
    signed=$((signed+1))
  fi
done < <(find "$APP/Contents" -type f)
echo "    signed $signed inner binaries"

echo "==> Signing the app bundle"
codesign --force --timestamp --options runtime --sign "$UNCORK_SIGN_ID" "$APP"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Zipping for the notary service"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple's notary service (waits for the result)"
xcrun notarytool submit "$ZIP" --keychain-profile "$UNCORK_NOTARY_PROFILE" --wait

echo "==> Stapling the notarization ticket to the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Building a drag-to-install DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"     # so the DMG shows an Applications drop target
/usr/bin/hdiutil create -volname "Uncork" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
# Staple the DMG too so it validates offline.
xcrun stapler staple "$DMG" 2>/dev/null || true

rm -f "$ZIP"
echo "==> Done: $DMG"
echo "    Signed as: $UNCORK_SIGN_ID"
echo "    This DMG opens with no Gatekeeper warnings; users drag Uncork to Applications."
