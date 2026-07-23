# Uncork - Per-Game Compatibility Profiles (troubleshooting feature)

Status: PLAN (2026-07-21). Analog of Steam-on-Linux's per-game "Compatibility" tab
(force a specific Proton version). Real need: e.g. Paw Patrol runs on an *older*
Proton but not the latest - same class of problem exists on Mac.

## 1. Core idea & the Mac twist

Steam lets you force a **Proton version** per game. On Mac we do the same, BUT the
Wine version and the graphics backend are **coupled** (proven this week: D3DMetal
libs are ABI-locked to GPTk Wine; DXMT's `winemetal.so` is locked to its Wine build;
mixing them → `c0000135` / version crashes). So we expose **compatibility profiles**
= matched, tested bundles of (Wine engine + graphics backend + default winver) - NOT independent Wine/backend dropdowns. This mirrors "Proton 7.0 / 8.0 / GE" being
whole bundles, and is safer + clearer.

## 2. Profile catalog (data-driven: `compat/profiles.json`)

| id            | Wine            | Backend  | Bundled?      | Best for |
|---------------|-----------------|----------|---------------|----------|
| `auto`        | resolved        | resolved | - | default: GPTk+D3DMetal if present, else Wine11+DXMT |
| `gptk`        | GPTk 7.7        | D3DMetal | downloaded    | modern D3D11/12 (RISK, AC, Horizon-class) |
| `wine11-dxmt` | Wine 11         | DXMT     | bundled       | D3D11 alternative when D3DMetal misbehaves |
| `wine11-dxvk` | Wine 11         | DXVK     | bundled       | D3D9-11 - ⚠ geometryShader-limited on Apple Silicon |
| `crossover24` | CrossOver 9.0   | D3DMetal(CX) | download   | CEF / 32-bit clients (future; see cef wall) |
| `wine10-dxmt` | Wine 10         | DXMT     | download      | "older Wine" bucket for games newer Wine breaks |

Catalog is JSON so it updates WITHOUT rebuilding the app (like `gamefixes.json`).
Each entry: `{ id, label, wine: {engineDir | downloadUrl, size}, backend, defaultWinver,
notes, verdictHint }`.

## 3. Data model

- **`compat/profiles.json`** (new) - the catalog above (shipped defaults, updatable).
- **`compat/gamefixes.json`** (exists) - add optional per-game `profile` default;
  keep `backend` (map backend→profile for back-compat).
- **`overrides.json`** (exists, per-user, wins over gamefixes) - extend per game:
  ```json
  { "312990": { "profile": "wine11-dxvk", "winver": "win7",
                "launch_args": "-force-d3d11", "dll_overrides": {"d3d9":"n"},
                "hud": false, "isolated_prefix": true } }
  ```

## 4. Engine download layer (`scripts/ensure-profile.sh <id>`)

Mirror `ensure-engine.sh`: idempotent; if the profile's Wine isn't on disk, download
its artifact from the catalog URL into the writable per-user engine dir
(`~/Library/Application Support/Uncork/engine/wine/<id>/`), extract, verify, emit
`@@STEP@@` progress. This is the direct analog of Steam downloading a Proton version.
Hosting: GPTk already comes from Gcenx releases; CrossOver from SikarugirCX;
additional Wine builds need durable URLs (same hosting task as the Steam snapshot).

## 5. Prefix handling (important)

Steam gives each game its own compat prefix per Proton version. Uncork shares one
`steam` bottle - and **switching Wine versions on a shared prefix conflicts**. So:
- A game on a **non-default profile** gets its **own bottle** (`isolated_prefix`
  already in the schema), named e.g. `steam-<appid>` or `steam-<profileid>`.
- Game *files* stay in the shared steamapps library; only the prefix changes. The
  library is symlinked into the alt prefix (play.sh already does this for GPTK_PREFIX).
- First use of a profile = one-time `wineboot --init` for its bottle (show progress).

## 6. play.sh wiring

Resolve profile: `overrides.json` > `gamefixes.json.profile` > `backend`→profile > `auto`.
Then: map profile → (engine `WINE_HOME`/GPTK, backend, prefix); call `ensure-profile.sh`
if that engine is missing (progress → UI); launch in the profile's prefix with the
profile's backend. Keep the existing DRM/crash **auto-fallback** as a within-profile
safety net.

## 7. App UI - per-game "Compatibility" panel

In the game's options (Library card → details), a section like Steam's:
- **Profile picker** - lists bundled + downloadable profiles; picking a not-yet-
  downloaded one shows a **download progress bar** (drives `ensure-profile.sh`).
- **Advanced** (collapsible): Windows version, launch args, DLL overrides, Metal HUD.
- **Verdict/hint line** from `gamefixes.json` (works / needs-work / unsupported) so
  users aren't blindly trying versions.
- **Reset to default.**
Writes to `overrides.json`; refreshes RunStore so the next Play uses it.

## 8. Honest guardrails (bake into UI copy)

- On Mac the **backend** fixes more than the Wine version; profiles bundle both.
- Some games are unfixable by ANY profile (graphics-fundamental, e.g. D3D9/32-bit,
  or broken on Linux too - check ProtonDB first: Linux is the floor).
- Each downloadable Wine is ~250-700 MB (fetched on demand, cached per-user).

## 9. Phasing

- **Phase 1 (no new downloads):** `profiles.json` + `overrides.json.profile` +
  play.sh resolution, exposing the 3 engines we ALREADY have (gptk, wine11-dxmt,
  wine11-dxvk) as switchable profiles + the UI picker. Immediate value.
- **Phase 2 (downloadable):** `ensure-profile.sh` + catalog URLs + UI download
  progress; add CrossOver 24, Wine 10, older Gcenx builds.
- **Phase 3 (isolation + advanced):** per-profile isolated bottles + winver / launch
  args / DLL-override UI.

## 10. Risks

- Prefix conflicts on the shared bottle → mitigated by per-profile bottles (Phase 3,
  but Phase 1 should at least warn / force isolated for non-default profiles).
- Hosting the downloadable Wines (durable URLs needed).
- First-use bottle init latency (show progress, cache).
