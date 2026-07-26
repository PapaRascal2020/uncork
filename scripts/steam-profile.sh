#!/usr/bin/env bash
# steam-profile.sh - pick a machine-appropriate Steam CLIENT config.
#
# Different Macs need different Steam client settings (an 8 GB M1 Air is far more
# fragile than a big M-series). Rather than force one set of flags on every machine
# (which regressed a working Mac once), we detect the machine and select a profile
# that decides the client launch flags, DLL overrides, and login strategy.
#
# Sourced by steam.sh / lib.sh. Sets: STEAM_PROFILE, STEAM_PROFILE_ARGS,
# STEAM_PROFILE_OVERRIDES, STEAM_PROFILE_LOGIN. Override detection with
# UNCORK_STEAM_PROFILE=standard|low-resource.
#
# Profiles:
#   standard      minimal known-good (verified on a big M-series): software CEF +
#                 keep our wrapper. Normal CEF sign-in.
#   low-resource  constrained Macs (<= 8 GB): add the stability flags Steam-on-Wine
#                 needs on weak hardware, and use -noreactlogin (the older, lighter
#                 login UI) so a FRESH sign-in - including a different account - can
#                 complete without the heavy React login crashing steamwebhelper.
#                 (Same-account reuse can still seed a saved session; -noreactlogin
#                 is what lets a NEW account log in on a fragile machine.)
#
# The single-process CEF wrapper is installed for ALL machines (it's what makes the
# UI render at all on Apple Silicon); it is NOT part of the profile.

steam_ram_gb() { echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )); }

steam_detect_profile() {
  if [[ -n "${UNCORK_STEAM_PROFILE:-}" ]]; then echo "$UNCORK_STEAM_PROFILE"; return; fi
  local ram; ram="$(steam_ram_gb)"
  # 8 GB or less: the constrained path. 0 (undetectable) falls back to standard.
  if [[ "$ram" -gt 0 && "$ram" -le 8 ]]; then echo "low-resource"; else echo "standard"; fi
}

# Populate STEAM_PROFILE_* for the given profile name.
steam_profile_config() {  # <profile>
  STEAM_PROFILE="$1"
  case "$1" in
    low-resource)
      # Stability set for weak Wine/Rosetta hosts (from Steam-Win-Silicon + our own
      # findings): no CEF sandbox, no controller service (CGamepadAPITask crash),
      # forced scaling, disable the flaky Steam service + menu builder + native dcomp,
      # and -noreactlogin for the lighter login UI so a fresh/other-account sign-in
      # can complete.
      STEAM_PROFILE_ARGS="-cef-disable-gpu -noverifyfiles -no-cef-sandbox -forcedesktopscaling 1 -nocontroller -noreactlogin"
      STEAM_PROFILE_OVERRIDES="steamservice=d;winemenubuilder.exe=d;dcomp=n"
      STEAM_PROFILE_LOGIN="noreactlogin"
      ;;
    *)  # standard (default, and anything unknown)
      STEAM_PROFILE="standard"
      STEAM_PROFILE_ARGS="-cef-disable-gpu -noverifyfiles"
      STEAM_PROFILE_OVERRIDES=""
      STEAM_PROFILE_LOGIN="cef"
      ;;
  esac
}
