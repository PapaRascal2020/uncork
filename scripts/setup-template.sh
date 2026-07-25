#!/usr/bin/env bash
# setup-template.sh - set up a generic store template (developer-added or an
# imported "Run Template" recipe) end-to-end: create a bottle, apply the recipe
# (Wine version is the engine the caller runs; OS/winver + winetricks + DLL
# overrides via apply-recipe.sh), and, if the template ships an installer URL,
# download + run it. Built-in kinds (steam/epic/gog) use their own setup-<kind>.sh.
#
# Usage: setup-template.sh <template-id>
# Reads the template JSON from the user dir first, then the shipped catalog.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

ID="${1:?usage: setup-template.sh <template-id>}"
DATA="${UNCORK_DATA:-$HOME/Library/Application Support/Uncork}"
USER_T="$DATA/templates/$ID.json"
CATALOG="$PROJECT_ROOT/compat/store-templates.json"

step 5 "Reading template '$ID'…"
# Extract fields with python (handles both a standalone file and the catalog entry).
read_field() {
  py - "$USER_T" "$CATALOG" "$ID" "$1" <<'PY'
import json,sys
user,catalog,tid,key=sys.argv[1:5]
t=None
try: t=json.load(open(user))
except Exception: pass
if t is None:
    try: t=json.load(open(catalog)).get("templates",{}).get(tid)
    except Exception: t=None
if not t: print(""); sys.exit(0)
# dotted key path e.g. recipe.winver / installer.url
cur=t
for p in key.split("."):
    if isinstance(cur,dict) and p in cur: cur=cur[p]
    else: cur=""; break
if isinstance(cur,(list,)): print(",".join(map(str,cur)))
elif isinstance(cur,dict):
    print(";".join(f"{k}={v}" for k,v in cur.items()))
else: print(cur if cur is not None else "")
PY
}

PLATFORM="$(read_field platform)"; PLATFORM="${PLATFORM:-windows}"
INSTALLER_URL="$(read_field installer.url)"
WAIT_FOR="$(read_field installer.wait_for_exe)"
WINVER="$(read_field recipe.winver)"
VERBS="$(read_field recipe.winetricks)"
DLLS="$(read_field recipe.dll_overrides)"
BOTTLE_NAME="template-$ID"

if [[ "$PLATFORM" == "mac" ]]; then
  # Native macOS store (e.g. itch.io): download the app archive + install the .app
  # into the per-user apps dir. No Wine, no bottle. Launch runs the .app directly.
  APPDIR="$DATA/apps/$ID"
  if [[ -n "$INSTALLER_URL" ]]; then
    step 20 "Downloading the macOS app…"
    CACHE="${UNCORK_CACHE:-$DATA/cache}"; mkdir -p "$CACHE" "$APPDIR"
    DL="$CACHE/$ID-mac.download"
    curl -sL "$INSTALLER_URL" -o "$DL" || die "Couldn't download the macOS app for '$ID'."
    step 65 "Installing the app…"
    tmp="$(mktemp -d)"
    # Extract the outer container: a zip, a tar, or a bare .dmg. (itch ships a ZIP
    # that CONTAINS a .dmg, so we may need a second step below.)
    if unzip -tq "$DL" >/dev/null 2>&1; then
      unzip -oq "$DL" -d "$tmp"
    else
      tar -xf "$DL" -C "$tmp" 2>/dev/null || true
    fi

    # Mount any .dmg (nested from the archive, or the download itself) and copy the
    # .app out of it, since a lot of Mac apps are delivered as a DMG.
    mount_dmg_app() {
      local dmg="$1" mnt a
      mnt="$(mktemp -d)"
      hdiutil attach -nobrowse -noverify -mountpoint "$mnt" "$dmg" >/dev/null 2>&1 || return 1
      a="$(find "$mnt" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)"
      [[ -n "$a" ]] && cp -R "$a" "$tmp"/ 2>/dev/null
      hdiutil detach "$mnt" >/dev/null 2>&1 || true
    }

    app="$(find "$tmp" -maxdepth 4 -name '*.app' -type d 2>/dev/null | head -1)"
    if [[ -z "$app" ]]; then
      # Look for a .dmg extracted from the archive; else the download itself is a dmg.
      dmg="$(find "$tmp" -maxdepth 3 -iname '*.dmg' 2>/dev/null | head -1)"
      [[ -z "$dmg" ]] && file "$DL" 2>/dev/null | grep -qiE "disk image|UDIF|Apple" && dmg="$DL"
      [[ -n "$dmg" ]] && mount_dmg_app "$dmg"
      app="$(find "$tmp" -maxdepth 4 -name '*.app' -type d 2>/dev/null | head -1)"
    fi
    [[ -n "$app" ]] || die "No .app found inside the download for '$ID'."
    rm -rf "$APPDIR"/*.app 2>/dev/null || true
    cp -R "$app" "$APPDIR"/
    xattr -cr "$APPDIR" 2>/dev/null || true
    rm -rf "$tmp" "$DL"
    step 100 "$ID installed."
    ok "Installed native macOS app for '$ID' into ${APPDIR#$DATA/}."
  else
    step 100 "Native macOS template ready (add its .app in the Library)."
    ok "Template '$ID' is native macOS; no installer URL, nothing to download."
  fi
  exit 0
fi

step 20 "Configuring the bottle (OS + components)…"
ARGS=()
[[ -n "$WINVER" ]] && ARGS+=(--winver "$WINVER")
[[ -n "$VERBS"  ]] && ARGS+=(--winetricks "$VERBS")
[[ -n "$DLLS"   ]] && ARGS+=(--dll "$DLLS")
bash "$(dirname "${BASH_SOURCE[0]}")/apply-recipe.sh" "$BOTTLE_NAME" "${ARGS[@]}" 2>&1 | sed 's/^/  /' || warn "Recipe apply had warnings."

if [[ -n "$INSTALLER_URL" ]]; then
  step 60 "Downloading the store installer…"
  CACHE="${UNCORK_CACHE:-$DATA/cache}"; mkdir -p "$CACHE"
  INST="$CACHE/$ID-installer.exe"
  curl -sL "$INSTALLER_URL" -o "$INST" || die "Couldn't download the installer for '$ID'."
  step 70 "Installing the store client…"
  # winver already applied by apply-recipe above; pass "" for it, plus wait_for_exe
  # so a self-updating installer (Battle.net) doesn't hang the whole setup.
  bash "$(dirname "${BASH_SOURCE[0]}")/install-custom-store.sh" "$BOTTLE_NAME" "$INST" "" "$WAIT_FOR" 2>&1 | sed 's/^/  /' || warn "Installer had warnings."
fi

step 100 "Template '$ID' ready."
ok "Set up template '$ID' in bottle '$BOTTLE_NAME'."
