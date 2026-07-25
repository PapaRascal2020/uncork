#!/usr/bin/env bash
# compatdb.sh: read the protonfixes-for-Mac database (compat/gamefixes.json).
# Source this, then use compat_get / compat_list. Pure data lookup; no wine.
#
#   compat_get <appid> <field>        # prints the field for a game, or ""
#   compat_get_json <appid> <field>   # for array fields (e.g. winetricks) -> newline list
#   compat_default <field>            # prints a defaults.* value
#
# Fields: title, engine, backend, verdict, launch_exe, notes, winetricks[]

COMPAT_DB="${COMPAT_DB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/compat/gamefixes.json}"
# Per-store setup data (prerequisites installed at Add-a-Store time). Self-derives
# to compat/stores.json next to gamefixes.json; overridable via STORES_DB.
STORES_DB="${STORES_DB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/compat/stores.json}"
# Per-user, per-game overrides the app writes (toggles like the Metal HUD). Same
# path the Swift app uses, so app + scripts agree without editing the shipped DB.
COMPAT_OVERRIDES="${COMPAT_OVERRIDES:-$HOME/Library/Application Support/Uncork/overrides.json}"

# These JSON lookups run through Uncork's Python (fetched on demand by lib.sh, which
# defines py()/UNCORK_PYTHON). Define a fallback so compatdb.sh also works standalone.
type py >/dev/null 2>&1 || py() { "${UNCORK_PYTHON:-/usr/bin/python3}" "$@"; }

compat_get() {  # <appid> <field>
  py - "$COMPAT_DB" "$1" "$2" <<'PY' 2>/dev/null
import json,sys
db,appid,field=sys.argv[1],sys.argv[2],sys.argv[3]
try: d=json.load(open(db))
except Exception: sys.exit(0)
g=d.get("games",{}).get(appid,{})
v=g.get(field, d.get("defaults",{}).get(field,""))
if isinstance(v,(list,dict)): sys.exit(0)
print(v if v is not None else "")
PY
}

compat_get_list() {  # <appid> <array-field>  -> one item per line
  py - "$COMPAT_DB" "$1" "$2" <<'PY' 2>/dev/null
import json,sys
db,appid,field=sys.argv[1],sys.argv[2],sys.argv[3]
try: d=json.load(open(db))
except Exception: sys.exit(0)
for x in d.get("games",{}).get(appid,{}).get(field,[]) or []: print(x)
PY
}

compat_default() {  # <field>
  py - "$COMPAT_DB" "$1" <<'PY' 2>/dev/null
import json,sys
db,field=sys.argv[1],sys.argv[2]
try: d=json.load(open(db))
except Exception: sys.exit(0)
print(d.get("defaults",{}).get(field,""))
PY
}

compat_env() {  # <appid>  -> KEY=VALUE lines from games[appid].env (object)
  py - "$COMPAT_DB" "$1" <<'PY' 2>/dev/null
import json,sys
db,appid=sys.argv[1],sys.argv[2]
try: d=json.load(open(db))
except Exception: sys.exit(0)
for k,v in (d.get("games",{}).get(appid,{}).get("env",{}) or {}).items(): print(f"{k}={v}")
PY
}

# Store setup lookups (compat/stores.json). ---------------------------------
store_get_list() {  # <store> <array-field>  -> one item per line
  py - "$STORES_DB" "$1" "$2" <<'PY' 2>/dev/null
import json,sys
db,store,field=sys.argv[1],sys.argv[2],sys.argv[3]
try: d=json.load(open(db))
except Exception: sys.exit(0)
for x in d.get("stores",{}).get(store,{}).get(field,[]) or []: print(x)
PY
}

# Prerequisite winetricks verbs to install into a store's bottle at setup time.
store_prereqs() { store_get_list "$1" prereqs; }

# Baseline winetricks verbs for EVERY store's D3DMetal prefix (top-level array in
# stores.json), so most games run with no per-game config.
gptk_baseline_verbs() {
  py - "$STORES_DB" <<'PY' 2>/dev/null
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
for x in d.get("gptk_baseline",[]) or []: print(x)
PY
}

# User override lookups (the app writes COMPAT_OVERRIDES). Missing file = empty.
compat_user_get() {  # <appid> <field>
  py - "$COMPAT_OVERRIDES" "$1" "$2" <<'PY' 2>/dev/null
import json,sys,os
f,appid,field=sys.argv[1],sys.argv[2],sys.argv[3]
if not os.path.exists(f): sys.exit(0)
try: d=json.load(open(f))
except Exception: sys.exit(0)
v=d.get(appid,{}).get(field,"")
if isinstance(v,bool): print("true" if v else "false")
elif isinstance(v,(list,dict)): sys.exit(0)
else: print(v if v is not None else "")
PY
}

# HUD on if the user override says so, else the DB's per-game/default 'hud'.
compat_hud_on() {  # <appid>  -> prints 1 if the Metal HUD should be enabled
  local u; u="$(compat_user_get "$1" hud)"
  if [[ "$u" == "true" ]]; then echo 1; return; fi
  if [[ "$u" == "false" ]]; then echo 0; return; fi
  local g; g="$(compat_get "$1" hud)"; [[ "$g" == "true" ]] && echo 1 || echo 0
}

# The Windows version Wine should report for this game: user override wins, then
# the DB's per-game 'winver', else empty (use the bottle default, normally win10).
# Values: win10 win81 win7 winvista win2k3 winxp  (Wine's -v tokens).
compat_winver() {  # <appid>
  local u; u="$(compat_user_get "$1" winver)"
  if [[ -n "$u" ]]; then echo "$u"; return; fi
  compat_get "$1" winver
}

# --- Compatibility PROFILES (compat/profiles.json) --------------------------
# A profile is a matched (Wine engine + graphics backend) bundle, the Mac analog
# of a Steam/Proton version. See compat/profiles.json. Engine follows from backend
# in play.sh (d3dmetal -> GPTk Wine, dxmt/dxvk -> Wine 11 + Steam), so a profile
# resolves to a BACKEND here.
PROFILES_DB="${PROFILES_DB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/compat/profiles.json}"

profile_get() {  # <profile-id> <field>  -> that profile's field (e.g. backend, label)
  py - "$PROFILES_DB" "$1" "$2" <<'PY' 2>/dev/null
import json,sys
db,pid,field=sys.argv[1],sys.argv[2],sys.argv[3]
try: d=json.load(open(db))
except Exception: sys.exit(0)
v=d.get("profiles",{}).get(pid,{}).get(field,"")
print(v if v is not None else "")
PY
}

# The profile selected for a game: user override 'profile' wins, then the DB's
# per-game 'profile', else "" (meaning: fall back to the game's backend / auto).
compat_profile() {  # <appid>
  local u; u="$(compat_user_get "$1" profile)"
  if [[ -n "$u" ]]; then echo "$u"; return; fi
  compat_get "$1" profile
}

# The effective graphics BACKEND for a game, honoring a selected profile:
#   selected profile (non-'auto') -> that profile's backend
#   else                          -> the game's per-game/default 'backend'
# Empty output = "auto" (play.sh then picks d3dmetal if GPTk is present, else dxmt).
compat_backend() {  # <appid>
  local prof; prof="$(compat_profile "$1")"
  if [[ -n "$prof" && "$prof" != "auto" ]]; then
    profile_get "$prof" backend
  else
    compat_get "$1" backend
  fi
}

# The d3dmetal ENGINE a profile uses (profiles.json engine_id), e.g. "gptk",
# "gptk-2.1". Empty for non-d3dmetal / unknown profiles → caller defaults "gptk".
compat_engine_id() {  # <appid>
  local prof; prof="$(compat_profile "$1")"
  [[ -z "$prof" || "$prof" == "auto" ]] && { echo ""; return; }
  profile_get "$prof" engine_id
}

# --- Advanced per-game toggles (Phase 3) ------------------------------------
# Effective launch args = DB launch_args + user override launch_args (appended).
compat_launch_args() {  # <appid>
  local db user
  db="$(compat_get "$1" launch_args)"
  user="$(compat_user_get "$1" launch_args)"
  printf '%s %s' "$db" "$user" | sed 's/^ *//;s/ *$//'
}

# Per-game DLL overrides as a WINEDLLOVERRIDES fragment ("d3d11=n;xaudio2_9=b"),
# read from the user overrides file's dll_overrides object. Empty if none.
compat_dll_overrides() {  # <appid>
  py - "$COMPAT_OVERRIDES" "$1" <<'PY' 2>/dev/null
import json,sys,os
f,appid=sys.argv[1],sys.argv[2]
if not os.path.exists(f): sys.exit(0)
try: d=json.load(open(f))
except Exception: sys.exit(0)
o=d.get(appid,{}).get("dll_overrides",{})
if isinstance(o,dict) and o:
    print(";".join(f"{k}={v}" for k,v in o.items()))
PY
}
