#!/usr/bin/env bash
# make-build-kit.sh - assemble a self-contained SOURCE + engine kit that another
# developer can build into a full Uncork.app on their OWN Mac. Building locally is
# what fixes the code-signing problem: package-app.sh ad-hoc signs the bundle on
# the machine that creates it, so there is no cross-machine signature corruption and
# no transfer quarantine (which is what breaks a pre-built .app you zip and send).
#
# The kit carries the app source + the bundled engines (wine-stable, wine-cef, dxvk,
# the Epic/GOG CLIs) so the built app works fully offline. It deliberately omits dev
# cruft (build output, app/.build, thirdparty, wine source, gptk, bottles).
#
# Usage: scripts/make-build-kit.sh [output-dir]   (default: ./build)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUT_DIR"
KIT="$OUT_DIR/uncork-build-kit.tar.gz"

# The build instructions that ship inside the kit.
README="$ROOT/BUILD-KIT-README.md"
cat > "$README" <<'MD'
# Uncork build kit

This kit contains everything needed to build a full, working `Uncork.app` on your
own Apple Silicon Mac. Build it locally: that is what avoids the code-signing issue
(the app is ad-hoc signed on the machine that creates it, so there is no transfer
quarantine or cross-machine signature corruption).

## Requirements
- Apple Silicon Mac (M1 or newer), macOS 14 or later.
- Xcode command-line tools: `xcode-select --install`
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`

## Build
```bash
tar -xzf uncork-build-kit.tar.gz
cd uncork-build-kit
bash scripts/package-app.sh          # produces build/Uncork.app, ad-hoc signed
```
Then double-click `build/Uncork.app`. First launch downloads the graphics engine
(and the Steam client, if you use Steam) into your user Library; everything else is
already bundled.

## Notes
- If you rebuild while the app is open, `package-app.sh` quits it first (repackaging
  over a running bundle corrupts the signature).
- `swift build` in `app/` is a quick compile check without packaging.
- This is the full kit (engines bundled). For a lean build that downloads the Wine
  engines on first use instead, run `UNCORK_SLIM=1 bash scripts/package-app.sh`.
MD

echo "==> Assembling build kit -> $KIT"
echo "    including: app source, scripts, compat, wine-fixes, tools, docs, engines"
# Tar straight from the source tree (no staging copy) with the engines included and
# dev cruft excluded. Symlinks + exec bits are preserved.
tar -czf "$KIT" \
  --exclude='.git' \
  --exclude='.DS_Store' \
  --exclude='app/.build' \
  --exclude='app/.swiftpm' \
  -s '#^#uncork-build-kit/#' \
  -C "$ROOT" \
  app scripts compat wine-fixes tools docs \
  engine/wine-stable engine/wine-cef engine/dxvk engine/legendary-venv engine/gogdl-venv \
  assets/Uncork.icns \
  BUILD-KIT-README.md 2>/dev/null || {
    # GNU tar has no -s; fall back to a transform (Linux) or a staged prefix.
    tar -czf "$KIT" --transform='s,^,uncork-build-kit/,' \
      --exclude='.git' --exclude='.DS_Store' --exclude='app/.build' --exclude='app/.swiftpm' \
      -C "$ROOT" \
      app scripts compat wine-fixes tools docs \
      engine/wine-stable engine/wine-cef engine/dxvk engine/legendary-venv engine/gogdl-venv \
      assets/Uncork.icns BUILD-KIT-README.md
  }

echo "==> Done: $KIT ($(du -h "$KIT" | cut -f1))"
echo "    Send this file. The developer unpacks it and runs: bash scripts/package-app.sh"
