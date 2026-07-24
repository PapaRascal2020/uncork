# Uncork: Developer Guide

Uncork runs Windows game launchers and games on Apple Silicon Macs, the
Mac-user-friendly way. This guide is for people hacking on Uncork itself. It is
open source; contributions welcome.

## The big picture

Uncork is **a SwiftUI app that drives shell scripts that drive Wine**. The app
is only the UI and orchestration. All the real work (creating bottles,
installing stores, launching games, applying fixes) lives in `scripts/` so it
can be fixed and shipped as data, without rebuilding the app.

```
SwiftUI app  --runs-->  scripts/*.sh  --drive-->  Wine + graphics backend
 (the UI)               (the engine)              (GPTk/D3DMetal, DXMT, DXVK)
```

Two roots keep the app relocatable (see `Support/Paths.swift`):

- **payload**: read-only. Shipped inside `Uncork.app/Contents/Resources/uncork`
  (`scripts/`, `tools/`, `compat/`, `engine/`, `wine-fixes/`, `docs/`); in dev
  it is the source checkout.
- **data**: writable per-user state at `~/Library/Application Support/Uncork`
  (`bottles/`, downloaded engines, `apps/`, `templates/`, `art/`,
  `overrides.json`, caches). Never written into the payload, so a signed bundle
  stays valid.

## Repository layout

| Path | What |
|------|------|
| `app/` | the SwiftUI app (SPM package; `Sources/Uncork/...`) |
| `scripts/` | the engine: bottle creation, store setup, `play.sh`, fixes |
| `compat/` | data-driven DBs: `gamefixes.json`, `profiles.json`, `store-templates.json` |
| `engine/` | Wine builds + graphics backends (large ones downloaded on demand) |
| `wine-fixes/` | versioned patched-Wine engines + `wine-builds.json` (Wine Downloader catalog) |
| `tools/` | small bundled CLIs |
| `docs/` | this guide + design docs |

## Key concepts

### Rosetta + the graphics backends

Windows games are x86-64. On Apple Silicon the whole stack runs **x86-64 Wine
under Rosetta 2**, with a DirectX to Metal translator on top. There is no native
Vulkan on macOS, so the working backends are:

- **D3DMetal** (Apple's, via the Game Porting Toolkit Wine): D3D11/12 to Metal.
  The fast, most complete path for modern games.
- **DXMT**: D3D11 to Metal, on the bundled Wine 11. The de-facto Steam backend.
  Built for **both architectures** (`lib/wine/x86_64-windows` and
  `i386-windows`), so **32-bit D3D11 games work too** (e.g. Among Us). When it
  loads as *builtin*, Wine picks the DLL matching the process arch automatically.
- **DXVK**: D3D9/10/11 to Vulkan to Metal (MoltenVK). Mostly **unusable on Apple
  Silicon**: DXVK requires the `geometryShader` Vulkan feature that MoltenVK
  cannot provide, so it usually cannot get a GPU. Kept for completeness.

Rule of thumb: 64-bit *and* 32-bit D3D11/12 games work (D3DMetal/DXMT). Old
D3D9 games are the remaining hard case. **Linux/Proton is the floor**: if a game
does not run there, it will not run on Mac (check ProtonDB before investing).

**Launch mechanism (important gotcha):** `play.sh` launches the game **exe
directly** (`wine "$GAME_EXE" $launch_args`), *not* `steam -applaunch`. Because
we start Steam hidden first, a second `steam -applaunch <id>` only IPCs the
already-running Steam, which spawns the game from its own process, so our
graphics env (`WINEDLLOVERRIDES` = builtin DXMT) and per-game `launch_args`
never reach the game. Direct launch puts them on the actual game process;
SteamStub DRM still decrypts (we write `steam_appid.txt` and wait for sign-in).
A `-applaunch` fallback fires only if the direct process exits within ~14s.

### Bottles (Wine prefixes)

A "bottle" is a Wine prefix under `data/bottles/`. Launcher games share their
store's bottle (`steam`, `epic`, `gog`); D3DMetal games use a per-engine prefix
(`steam-gptk`, `steam-gptk-2.1`, ...); standalone/added games can be isolated.
Stopping a game only ever targets its own prefix via `wineserver -k`: **never a
system-wide `pkill`**.

### The compat DB: `compat/gamefixes.json`

Uncork's "protonfixes-for-Mac": one source of truth for per-game fixes, read by
`scripts/autoconfigure.sh`, `scripts/play.sh`, and the app. Per game: `backend`,
`verdict`, `launch_exe`, `winetricks[]`, `env{}`, `launch_args`, `notes`. Update
it to fix a game, no app rebuild needed.

### Compatibility profiles: `compat/profiles.json`

The Mac analog of Steam's per-game Proton-version picker. A **profile** is a
matched (Wine engine + graphics backend) bundle, because the two are ABI-coupled
here. Profiles: `auto`, `gptk` (D3DMetal), `wine11-dxmt`, `wine11-dxvk`, plus
downloadable older `gptk-2.1` / `gptk-1.1`. `scripts/ensure-profile.sh` fetches
a profile's engine on demand.

### User overrides: `overrides.json`

Per-user, per-game choices the app writes and the scripts read: `profile`,
`backend`, `winver`, `hud`, `launch_args`, `dll_overrides`. Always wins over the
shipped DB, so a UI toggle takes effect on the next launch.

Steam games tune via the profile picker (`profile` → `compat_backend` in play.sh).
**Epic and GOG** get a direct backend dropdown (`backend`: auto / d3dmetal / dxmt)
plus launch options on the game page; the app passes these to `epic.sh`/`gog.sh` as
`UNCORK_BACKEND` and `UNCORK_LAUNCH_ARGS`. Those scripts default to D3DMetal, launch
the DXMT choice by direct-running the exe with the DXMT/Metal env (mirroring play.sh,
so `legendary`/`gogdl launch` can't drop the graphics env or the args), and append
the launch args to whichever path runs. So every store's games now have per-game
compatibility options, not just Steam.

## Stores: data-driven templates

Stores are **data-driven and extensible**. The catalog is
`compat/store-templates.json`, and developers add a store by adding a template,
with no app rebuild. Loaded by `StoreTemplates` (app) and `setup-template.sh`
(engine). Any `*.json` dropped in `data/templates/` is also loaded, and
overrides a shipped template with the same id.

A template has an `id`, `name`, `platform`, art, a reproducible `recipe`
(engine + winver + winetricks + dll_overrides + launch_flags + env), an optional
`store_url`, and, for installable ones, an `installer` (url, optional
`wait_for_exe`) plus `launch_path` / `detect_path`.

Set `store_url` to a store's web storefront (buy/claim page) to let users browse
it inside Uncork: once the store is installed, a row for it appears under the
sidebar's "Browse" section and opens the page in an embedded, persistent-login
web view. Steam, Epic and GOG ship with one. Custom stores get the same field in
the Add-a-Store sheet, so a user's own launcher can have a store page too.

Two axes:

- **`kind`**: `steam` / `epic` / `gog` are **built-in kinds** with a dedicated
  `setup-<kind>.sh`. `generic` templates are set up by the shared
  `setup-template.sh`.
- **`platform`**: `windows` installs into a Wine bottle
  (`bottles/template-<id>`); `mac` installs a **native macOS app** (no Wine) into
  `data/apps/<id>/` and launches it with `run-mac.sh`.

Shipped templates:

- **Steam** (built-in): the ~2 GB client snapshot is downloaded on first run
  (not bundled) from `STEAM_CLIENT_SNAPSHOT_URL` and unpacked into the writable
  data dir. Games launch via `play.sh`.
- **Epic** (built-in): the `legendary` CLI (`scripts/epic.sh`), run relocatably.
  Pass `--platform Windows` to pull Windows builds on a Mac.
- **GOG** (built-in): the `gogdl` CLI (`scripts/gog.sh`).
- **Battle.net** (generic, **native mac**): installs Blizzard's real macOS
  Battle.net, so it runs with no Wine and avoids the Windows installer's Update
  Agent stall. Blizzard games with a Mac build run natively.
- **itch.io** (generic, **native mac**): installs the native itch app.

### Custom stores and Save/Run templates

- **Custom stores** (`CustomStoresStore` + `install-custom-store.sh`): a user
  adds any storefront themselves, Windows (installer run in a fresh bottle, with
  a chosen Wine engine + winver + flags, then pick the launcher exe) or native
  macOS (`.app` shortcut). Persisted to `custom-stores.json`.
- **Save as Template / Run Template** (`TemplateService`): export a perfected
  bottle's recipe to a shareable `.json`, or import one, so anyone can reproduce
  a bottle exactly. Exports land in `data/templates/`.

### Hard-walled launchers (native beats Wine)

Launchers that wall under Wine (EA app gRPC BGS, Battle.net Update Agent/WMI,
Rockstar background service) wall because of a background service, not the game.
Two escapes: prefer the vendor's **native macOS client** (Battle.net, Steam), or
use a **download CLI** that pulls the Windows files for us to Wine-run
(`legendary`/`gogdl`, and Steam's `steamcmd` with
`+@sSteamCmdForcePlatformType windows`). EA and Rockstar have neither, so they
stay blocked; those games are often available on Steam/Epic instead.

## Wine Downloader: `wine-fixes/wine-builds.json`

The Wine Downloader (a Wine-Manager screen, Heroic-style) lists standalone Wine
builds fetched on demand into `engine/wine-builds/<id>` by
`scripts/ensure-wine-build.sh`. Distinct from `profiles.json` engines (matched
Wine + backend the game pickers use): a Wine Build is a raw runtime you can trial
when a game misbehaves, including **older versions** to roll back to. Add a build
to the JSON and it appears with no app rebuild.

## Library and artwork

The Library is one grid of every owned game across stores plus user-added apps,
with **Mac | Windows | All** platform tabs and a per-tile platform badge. Add a
game directly: **Add Windows Game** (an `.exe` via Wine) or **Add Mac Game** (a
native `.app`).

**Install state** reads at a glance: an installed tile shows full-colour art with a
small green check; a not-installed tile is dimmed and carries a download "NOT
INSTALLED" badge (and a live progress chip while downloading).

**Organization** (`LibraryOrganizer`, persisted to `library-org.json`) adds
favorites, hidden games, and custom collections, all keyed by game id. Each tile has
a visible star toggle and a "⋯" menu (hide, collections, new collection); right-click
does the same. The filter menu adds **Favorites only**, **Show hidden** (hidden games
are set aside otherwise), and a **Collection** picker. Empty collections are pruned
automatically, so there's no separate delete step.

**Verify & repair** (`RepairService`): the game page runs `legendary repair` /
`gogdl repair` (both re-run the installer in repair mode: re-check files, re-download
what's bad) for Epic/GOG. Steam integrity checks stay in the Steam client. The
service drains the child's pipe so a long repair can't block.

**Install location** (`InstallLocationService` + `scripts/install-location.sh`, Epic/
GOG): the store card's "Install location…" symlinks the store's install root
(`drive_c/EpicGames`, `drive_c/GOG Games`) to a folder the user picks, moving any
existing games first. Symlinking the parent means recorded per-game paths still
resolve, so both existing and future installs live at the target. Steam libraries are
the Steam client's job and aren't offered here.

**Anti-cheat** is a data-driven expectation: a compat-DB `anticheat` field (the tech
name, e.g. "Easy Anti-Cheat"/"BattlEye") shows a red hard-limit warning on the game
page, since EAC/BattlEye have no macOS runtime and no Uncork fix exists. Pair it with
`verdict: "unsupported"`.

The game detail page is Steam-styled: a wide `library_hero` banner with the
transparent game `logo` overlaid. For titles Uncork cannot pull art for (or to
override what it did), **custom artwork** (`CustomArtStore`) lets the user set a
banner or a cover image; the picked file is copied into `data/art/` and always
wins over CDN art.

### Cloud saves

Epic and GOG saves sync through the same CLIs Uncork already bundles. **Epic** goes
through `legendary sync-saves <app>` (via the `epic.sh` passthrough; legendary
resolves the save path from the game's `CloudSaveFolder` metadata against the epic
bottle). **GOG** goes through `gogdl save-sync <path> <id> --os windows --ts <ts>`
(the `gog.sh save-sync` command); GOG needs the save folder set explicitly and a
last-sync timestamp. **Steam** saves are Steam Cloud's job inside the client, so
Uncork does not manage them; custom games have no cloud.

The scripts stay stateless: the app's `CloudSaveStore` owns `cloud-saves.json`
(per-game save folder + last-sync time) and passes those in, and `CloudSaveService`
runs the sync (two-way, or force upload/download) and marks the time on success.
The detail page's Cloud saves card exposes Sync / Upload / Download and a save-folder
picker rooted at the game's bottle. Auto-sync on launch/close is a deliberate
follow-up (kept manual for now so a wrong save folder can't clobber the cloud).

## App to script contract

The app spawns scripts with `Paths.scriptEnvironment(...)`, which points them at
the payload (engine/tools) and the data dir (bottles). Scripts stream progress:

- `@@STEP@@ <pct> <msg>`: setup/download progress to a progress bar.
- `@@STATUS@@ <msg>`: live launch status to the Play button.
- `FOUND_EXE=<path>`: a custom-store install reports the launcher exe it found.

### Launch logs

Each launch writes a per-game log the user (and you) can inspect when a game
misbehaves. The app passes `UNCORK_GAME_LOG=<data>/logs/<id>.log` in the launch
env; `lib.sh` sets `GAME_LOG` to it (or `/dev/null` when unset, so a manual run is
unchanged) and the `log`/`ok`/`warn`/`die` helpers mirror their narration there.
The launch scripts (`play.sh`, `epic.sh`, `gog.sh`, `run-exe.sh`) call
`game_log_init` for a header, then redirect the **game process's own** stdout/stderr
to `$GAME_LOG`, so the file captures both Uncork's steps (backend, DRM detection,
fallbacks, warnings) and the game's own output (e.g. a game's "no valid graphics
device" message). `GameLog` (app) resolves the path and `LogView` shows it on the
game page (copy / reveal / refresh). Note the default launch keeps `WINEDEBUG=-all`,
so Wine's internal channels are quiet: the log is the game's output plus Uncork's
narration, not a full Wine trace.

**Diagnostic relaunch.** The game page's "Relaunch with diagnostics" button launches
with `UNCORK_DIAGNOSTIC=1`. When set (and the user hasn't pinned `WINEDEBUG`), `lib.sh`
raises the level to `WINEDEBUG=err+all,fixme-all`, so the log then captures Wine's own
errors (dll load failures, HRESULTs, device-creation errors), with fixme kept off to
avoid flooding. The log header records that diagnostic mode was on. It rides the same
`${WINEDEBUG:--all}` every launch site already reads, so no per-path change is needed.

On quit, Uncork sends the prewarmed Steam client a clean `-shutdown` **off the
main thread**, hides its window, and shows a small "Closing" HUD, so app-quit is
a deliberate step, not a frozen window.

## Build and run

Requirements: macOS on Apple Silicon, Xcode command-line tools, Rosetta 2
(`softwareupdate --install-rosetta --agree-to-license`).

```bash
# dev run (uses the source tree as the payload)
cd app && swift run

# build a double-clickable, signed Uncork.app bundle
bash scripts/package-app.sh      # -> build/Uncork.app
```

`swift build` for a quick compile check. The GPTk graphics engine and the Steam
client are **downloaded on first run**, not bundled, to keep the app lean.
`package-app.sh` quits any running Uncork first (repackaging over a live bundle
corrupts its signature), then re-signs and verifies.

### Slim builds and on-demand engines

`UNCORK_SLIM=1 bash scripts/package-app.sh` omits the two big Wine engines
(`wine-stable`, `wine-cef`, roughly 1.8 GB) from the bundle. They are then fetched
on first use into the writable per-user engine dir by `scripts/ensure-wine-engine.sh`
(`wine-stable` from `WINE_STABLE_ASSET_URL`; `wine-cef` from `WINE_CEF_URL`). The
resolver in `lib.sh` prefers a bundled engine and falls back to the per-user dir, so
the same code path works bundled or slim. The default build still bundles both.

Our `wine-stable` is NOT the public Gcenx build: it has DXMT (DirectX->Metal) baked
in (a ~20 MB `d3d11.dll` plus the `winemetal.dll` / `winemetal.so` Metal bridge),
which is how DirectX 11 games render. The public Gcenx release ships only the tiny
stock `wined3d` `d3d11` and no `winemetal`, so a slim build must fetch our hosted
engine, not Gcenx, or every DirectX 11 game fails with a missing/failed D3D11 device.
`ensure-wine-engine.sh` treats a per-user engine that lacks `winemetal.so` as stock
and re-fetches ours over it, so an install broken by an earlier (Gcenx-fetching)
slim build self-heals on the next launch once the asset is hosted.

DXVK and the Epic/GOG clients are also fetched on demand by `scripts/ensure-cli.sh`
(DXVK from the upstream release; `legendary` and `gogdl` installed with the system
`python3`), so a bare source clone builds a fully working app without the build kit.

The on-demand assets (`wine-stable` with DXMT, `wine-cef`, and the Steam client
snapshot) are hosted on GitHub releases;
`scripts/upload-assets.sh [all|wine-stable|wine-cef|steam]` packages and uploads them
(needs `gh` authenticated with write access to the repo). The `wine-stable` packer
refuses to upload a tree that is not the DXMT engine, so it cannot reship the bug.

### Handing the build to another developer

Building on the target Mac avoids the code-signing problem (a pre-built `.app` that
is zipped and sent picks up transfer quarantine and a cross-machine signature that
Gatekeeper rejects). `scripts/make-build-kit.sh` assembles
`build/uncork-build-kit.tar.gz`: the app source plus the bundled engines, minus dev
cruft (`app/.build`, `thirdparty/`, wine source, gptk, bottles) and a
`BUILD-KIT-README.md`. The recipient unpacks it and runs `bash scripts/package-app.sh`
to get a locally-signed `Uncork.app`.

## How to contribute a fix

- **Make a game work:** add/tune its entry in `compat/gamefixes.json` (pick a
  `backend`, set `launch_exe`, add `winetricks`, record a `verdict` + `notes`).
- **Add a compatibility profile / engine version:** add it to
  `compat/profiles.json` (with `engine_id` + `download` for a fetchable engine).
- **Add a store:** add a template to `compat/store-templates.json` (or drop a
  `.json` in `data/templates/`). Generic templates need no code; built-in kinds
  have a `setup-<kind>.sh`.
- **Add a Wine build:** add an entry to `wine-fixes/wine-builds.json`.
- **Patch Wine itself:** when no open-source fix exists, patch + build Wine,
  tracked in `wine-fixes/`, and open-source the patch.

Keep fixes **portable** (they must work on any Mac from a clean install) and
**data-driven** where possible (so they ship without an app rebuild). Anything a
user would otherwise do by hand should become an automated, shipped step.

## Known limits (be honest in the UI)

- 32-bit + D3D9 games: no working D3D-to-Metal path yet (DXMT is D3D10/11-only;
  DXVK hits the geometryShader wall). 32-bit **D3D11** now works via DXMT.
- CEF launcher clients (EA/Ubisoft): 32-bit Chromium needs a matched D3DMetal
  that the extracted Wine lacks, a known wall.
- EA app / Rockstar launchers: hard-walled on macOS Wine (background-service
  bugs); no native Mac client to fall back to.
- The whole engine is x86-64 under Rosetta 2; a native-ARM successor (ARM Wine +
  FEX + Metal) is tracked but not viable yet. The engine layer is kept swappable
  on purpose.
