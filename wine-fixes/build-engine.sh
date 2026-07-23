#!/usr/bin/env bash
# build-engine.sh: build a versioned, patched Uncork Wine engine from source.
#
# This is Uncork's analogue of Proton's build + patch pipeline: it fetches a base
# Wine source (CrossOver LGPL tarball), applies our tracked wine-fixes/patches/, and
# produces a runnable, versioned engine tree. Naming: uncork-<uncork_ver>-wine-<wine_ver>.
#
# Usage:  wine-fixes/build-engine.sh <recipe-file>
#   e.g.  wine-fixes/build-engine.sh wine-fixes/recipes/uncork-1.0-wine-11.0.recipe
#
# A recipe is a small env file defining: ENGINE_ID, SOURCE_URL, PATCHES (space list),
# CONFIGURE_FLAGS, and (optional) POST_BUILD hooks. See recipes/ for examples.
#
# Toolchain gotchas this script handles automatically:
#   - macOS bison is too old: use brew bison in PATH
#   - missing include/distversion.h: create it (patch 0002)
#   - __ASM_CFI cfi error on clang 17+: patch 0001
#   - SONAME_LIBVULKAN undefined under --without-vulkan: patch 0003 (post-configure)
#   - x86_64 native build (wine-cef/Rosetta target): CC="clang -arch x86_64"
#   - GCC16 mingw breaks a few optional PE programs: make -k (keep going)
set -euo pipefail

RECIPE="${1:?usage: build-engine.sh <recipe-file>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXES="$ROOT/wine-fixes"
WORK="${WINE_BUILD_WORK:-$HOME/wine-cx-build}"
BISON_BIN="$(brew --prefix bison 2>/dev/null)/bin"

# shellcheck disable=SC1090
source "$RECIPE"
: "${ENGINE_ID:?recipe must set ENGINE_ID}" "${SOURCE_URL:?recipe must set SOURCE_URL}"
CONFIGURE_FLAGS="${CONFIGURE_FLAGS:---enable-archs=i386,x86_64 --disable-winedbg --without-x --without-vulkan --without-freetype --disable-tests --host=x86_64-apple-darwin}"

log(){ printf '\033[34m==>\033[0m %s\n' "$*"; }

mkdir -p "$WORK"; cd "$WORK"
TARBALL="$(basename "$SOURCE_URL")"
SRCDIR="$WORK/${ENGINE_ID}-src"

log "Engine: $ENGINE_ID   (patches: ${PATCHES:-none})"
[[ -f "$TARBALL" ]] || { log "Downloading $SOURCE_URL"; curl -L --fail -o "$TARBALL" "$SOURCE_URL"; }
[[ -d "$SRCDIR" ]] || { log "Extracting → $SRCDIR"; mkdir -p "$SRCDIR"; tar xzf "$TARBALL" -C "$SRCDIR"; }
WINE="$(find "$SRCDIR" -maxdepth 3 -name configure -path '*wine*' | head -1 | xargs dirname)"
[[ -n "$WINE" ]] || { echo "no wine source under $SRCDIR"; exit 1; }
log "Wine source: $WINE"

# --- distversion.h (patch 0002) ---
printf '#define WINDEBUG_WHAT_HAPPENED_MESSAGE "An application error occurred."\n#define WINDEBUG_USER_SUGGESTION_MESSAGE "Please report this problem."\n' \
  > "$WINE/include/distversion.h"
cp "$WINE/include/distversion.h" "$WINE/../distversion.h" 2>/dev/null || true

# --- __ASM_CFI on Apple (patch 0001) ---
python3 - "$WINE/include/wine/asm.h" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
old='#if defined(__GCC_HAVE_DWARF2_CFI_ASM) || ((defined(__APPLE__) || defined(__clang__)) && defined(__GNUC__) && !defined(__SEH__))\n# define __ASM_CFI(str) str\n#else\n# define __ASM_CFI(str)\n#endif'
new='#if defined(__APPLE__)\n# define __ASM_CFI(str)\n#elif defined(__GCC_HAVE_DWARF2_CFI_ASM) || ((defined(__APPLE__) || defined(__clang__)) && defined(__GNUC__) && !defined(__SEH__))\n# define __ASM_CFI(str) str\n#else\n# define __ASM_CFI(str)\n#endif'
if old in s: open(p,'w').write(s.replace(old,new)); print("  asm.h: CFI disabled on Apple")
else: print("  asm.h: already patched or pattern changed - verify")
PY

# --- apply any additional real .patch files listed in the recipe ---
for pset in ${PATCHES:-}; do
  pf="$FIXES/patches/$pset.patch"
  if grep -q '^--- a/' "$pf" 2>/dev/null; then
    log "Applying $pset"; (cd "$WINE" && patch -p1 < "$pf") || echo "  (patch $pset needs manual review)"
  else
    log "Note: $pset is a documented/manual patch (see $pf) - apply per its notes"
  fi
done

# --- configure (x86_64 native, brew bison) ---
export PATH="$BISON_BIN:$PATH"
mkdir -p "$WINE/build-cx"; cd "$WINE/build-cx"
rm -f config.status config.cache
log "configure $CONFIGURE_FLAGS"
CC="clang -arch x86_64" CXX="clang++ -arch x86_64" MACOSX_DEPLOYMENT_TARGET=10.14 \
  ../configure $CONFIGURE_FLAGS

# --- SONAME_LIBVULKAN (patch 0003, post-configure, only if --without-vulkan) ---
if grep -q 'without-vulkan' <<<"$CONFIGURE_FLAGS"; then
  sed -i '' 's|/\* #undef SONAME_LIBVULKAN \*/|#define SONAME_LIBVULKAN "libvulkan.1.dylib"|' include/config.h 2>/dev/null || \
  python3 -c "p='include/config.h';s=open(p).read().replace('/* #undef SONAME_LIBVULKAN */','#define SONAME_LIBVULKAN \"libvulkan.1.dylib\"');open(p,'w').write(s)"
  log "SONAME_LIBVULKAN defined"
fi

# --- build + install ---
STAGE="$WORK/${ENGINE_ID}-root"
log "Building (make -k) …"; make -k -j"$(sysctl -n hw.ncpu)" || true
log "Installing → $STAGE"; rm -rf "$STAGE"; make -k install DESTDIR="$STAGE" >/dev/null 2>&1 || true
WINEBIN="$(find "$STAGE" -maxdepth 5 -name wine -type f | head -1)"
[[ -n "$WINEBIN" ]] && { log "DONE: $ENGINE_ID → $("$WINEBIN" --version 2>/dev/null || echo built) at $STAGE"; } || echo "install produced no wine binary - check the log"

# --- POST_BUILD hook (e.g. graft DXMT + winemac IOSurface consumer) ---
declare -F post_build >/dev/null && { log "Running recipe post_build…"; post_build "$STAGE" "$WINE"; }
