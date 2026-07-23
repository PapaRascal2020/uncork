#!/usr/bin/env bash
# apply-recipe.sh: configure a Wine bottle to match a store template's recipe so
# "Run Template" reproduces a setup exactly: the Windows version the bottle reports
# (OS/winver), winetricks verbs, and DLL overrides. The Wine ENGINE/version is
# selected by the caller (which wine runs the bottle) and recorded in the template.
#
# Usage:
#   apply-recipe.sh <bottle> [--winver win10] [--winetricks "corefonts,vcrun2022"] \
#                            [--dll "d3d11=b;dxgi=b"]
# Emits @@STEP@@ progress. Best-effort: a failed verb never aborts the whole recipe.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step() { printf '@@STEP@@ %s %s\n' "$1" "$2"; }

BOTTLE_NAME="${1:?usage: apply-recipe.sh <bottle> [flags]}"; shift
PFX="$BOTTLES_DIR/$BOTTLE_NAME"
WINE="$WINE_HOME/bin/wine"; WINESERVER="$WINE_HOME/bin/wineserver"
export WINEPREFIX="$PFX" WINEDEBUG="${WINEDEBUG:--all}" WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=n;mshtml=}"
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_HOME/lib:$WINE_HOME/lib/wine/x86_64-unix${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

WINVER=""; VERBS=""; DLLS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --winver) WINVER="${2:-}"; shift 2 ;;
    --winetricks) VERBS="${2:-}"; shift 2 ;;
    --dll) DLLS="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# Ensure the bottle exists.
if [[ ! -e "$PFX/system.reg" ]]; then
  step 5 "Creating the bottle…"
  "$WINE" wineboot --init >/dev/null 2>&1 || true
  "$WINESERVER" -w 2>/dev/null || true
fi

# --- OS / Windows version ---------------------------------------------------
# winetricks sets winver reliably (win10/win7/winxp/…). If winetricks isn't
# available we set the core CurrentVersion keys directly (good enough for most).
if [[ -n "$WINVER" ]]; then
  step 25 "Setting Windows version to $WINVER…"
  if command -v winetricks >/dev/null 2>&1; then
    WINE="$WINE" WINESERVER="$WINESERVER" winetricks -q "$WINVER" >/dev/null 2>&1 || warn "winetricks $WINVER failed (best-effort)."
  else
    case "$WINVER" in
      win10) cv=10.0; csd="" ;;
      win7)  cv=6.1;  csd="Service Pack 1" ;;
      winxp) cv=5.1;  csd="Service Pack 3" ;;
      *)     cv=10.0; csd="" ;;
    esac
    "$WINE" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentVersion /d "$cv" /f >/dev/null 2>&1 || true
    [[ -n "$csd" ]] && "$WINE" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CSDVersion /d "$csd" /f >/dev/null 2>&1 || true
    warn "winetricks not found - set CurrentVersion only (winver best-effort)."
  fi
fi

# --- DLL overrides (reliable via registry) ----------------------------------
if [[ -n "$DLLS" ]]; then
  step 55 "Applying DLL overrides…"
  IFS=';' read -ra pairs <<< "$DLLS"
  for p in "${pairs[@]}"; do
    dll="${p%%=*}"; mode="${p#*=}"
    [[ -z "$dll" || -z "$mode" ]] && continue
    # n=native, b=builtin, "n,b"=native,builtin: expand shorthands.
    case "$mode" in
      n) val="native" ;; b) val="builtin" ;; nb|n,b) val="native,builtin" ;; bn|b,n) val="builtin,native" ;; *) val="$mode" ;;
    esac
    "$WINE" reg add 'HKCU\Software\Wine\DllOverrides' /v "$dll" /d "$val" /f >/dev/null 2>&1 || true
  done
fi

# --- winetricks verbs -------------------------------------------------------
# Reuse install-runtime.sh (handles ngen-safe verb installs into the bottle).
if [[ -n "$VERBS" ]]; then
  step 70 "Installing runtime components ($VERBS)…"
  IFS=',' read -ra verbs <<< "$VERBS"
  BOTTLE_NAME="$BOTTLE_NAME" bash "$(dirname "${BASH_SOURCE[0]}")/install-runtime.sh" "${verbs[@]}" 2>&1 | sed 's/^/  /' || warn "Some verbs failed (best-effort)."
fi

step 100 "Recipe applied to '$BOTTLE_NAME'."
ok "Configured bottle '$BOTTLE_NAME' from recipe."
