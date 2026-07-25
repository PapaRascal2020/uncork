# Contributing to Uncork

Thanks for helping bring PC gaming to the Mac. Uncork is built to be extended, and
the most valuable contributions are often not code at all: a tested game result, a
one-line compatibility fix, or a new store template.

By contributing you agree that your work is licensed under the project's
**GPL-3.0** license (see `LICENSE`).

## Scope

Uncork targets **Mac gaming on Apple Silicon**: storefronts (Steam, Epic, GOG,
and native Mac launchers) and the games they sell. General Windows productivity
software is out of scope. Titles with kernel-level anti-cheat (Easy Anti-Cheat,
BattlEye) cannot run on Apple Silicon, because those anti-cheats have no macOS
runtime, so please flag them rather than trying to force them.

## Ways to contribute

- **Report a game result.** Tell us a title works, half-works, or fails, and how.
  This is the single most useful thing you can do.
- **Add or improve a game fix.** Most per-game settings are data in
  `compat/gamefixes.json`, so a fix is usually a few lines, no rebuild.
- **Add a store.** A new storefront is a template in `compat/store-templates.json`.
- **Contribute a Wine engine recipe or patch** under `wine-fixes/`.
- **Improve the app or docs.**

## Reporting a game

Open an issue with:

- The game, its store, and its ID (Steam appid, or the title for Epic/GOG).
- Your Mac (chip and macOS version).
- What happened: does it launch, render, and play, or where does it stop?
- The **launch log**. In the app, open the game's page, choose **View launch log**,
  and copy it. If the game crashed on fullscreen or graphics, that log usually says
  why.

Honest, specific reports ("black screen after the intro video on M1, works on M3")
are far more useful than "does not work".

## Adding a game fix

The compatibility database is `compat/gamefixes.json`, keyed by launch id (a Steam
appid, an Epic app_name, or a GOG id) with a `store` field. Add or edit an entry:

```json
"227300": {
  "title": "Euro Truck Simulator 2",
  "store": "steam",
  "verdict": "works",
  "backend": "d3dmetal",
  "winver": "win10",
  "launch_args": "-rdevice dx11",
  "notes": "Force the DirectX 11 renderer with -rdevice dx11 so it draws through D3DMetal; the default OpenGL path fails under Wine on macOS."
}
```

Useful fields:

- `verdict`: `works`, `needs-work`, `unsupported`, or `untested`.
- `backend`: `d3dmetal` (default), `dxmt`, or `dxvk`.
- `launch_args`: extra arguments passed to the game.
- `winver`: the Windows version Wine reports (`win10`, `win7`, and so on).
- `virtual_desktop`: `true` to run in a screen-sized window (the "Fullscreen (safe)"
  behavior) for games that crash on exclusive fullscreen.
- `anticheat`: name the tech (for example "Easy Anti-Cheat") for titles that cannot
  run; pair it with `verdict: "unsupported"`.
- `notes`: a short, plain-language explanation of what you did and why.

Only set `verdict: "works"` for something you have actually run and seen work.
Mark anything you have not confirmed as `untested` or `needs-work`.

## Adding a store

Add an entry to `compat/store-templates.json`. Native Mac launchers install as their
real `.app`; Windows launchers install into a Wine bottle. See the schema notes at
the top of that file and the "Stores" section of `docs/DEVELOPERS.md`.

## Building and testing

```bash
git clone https://github.com/PapaRascal2020/uncork.git
cd uncork
UNCORK_SLIM=1 bash scripts/package-app.sh    # produces build/Uncork.app
```

- `swift build` inside `app/` is a quick compile check.
- Data-only changes (compat DB, store templates) do not need a rebuild; the app and
  scripts read them at runtime.
- Please test a real launch of any game you add a fix for, and say in the PR what
  you tested on (chip and macOS version).

Detailed architecture is in `docs/DEVELOPERS.md`.

## Submitting changes

- Work on a branch and open a pull request against `main`.
- Keep changes focused; a single game fix or store per PR is easy to review.
- Describe what you changed and what you verified.
- You do not need to commit engines or other large binaries; they are downloaded
  on demand and are gitignored.

## Giving back to upstream

Uncork is built on other people's open-source work, and we treat contributing back
as part of the job, not an afterthought. When a fix we make belongs upstream, it
goes upstream:

- **Wine fixes** (anything in `wine-fixes/patches/`) are prepared as WineHQ patches
  and submitted to the Wine project, so they are not carried as a private fork
  forever. The patch catalog in `wine-fixes/` tracks upstream status.
- **DXMT** fixes and findings go to https://github.com/3Shain/dxmt.
- **CrossOver / CodeWeavers**: our CEF engine builds on CrossOver's Wine, which
  CodeWeavers releases under the LGPL and largely funds. We comply with the LGPL
  (corresponding source plus `THIRD-PARTY-NOTICES.md`), send Wine-level fixes
  upstream where CrossOver can benefit, and credit CodeWeavers openly. We do not want
  a one-way relationship: if Uncork is useful to you, please consider buying
  CrossOver to support the people who keep Wine on Mac alive.
- **Everything custom we build** (for example the 32-bit DXMT work) is published so
  the wider Mac-gaming community can use it.

If a change you send touches one of these components, note in the PR whether it
should also go upstream, and we will help route it.

## Code and comment style

Committed files are public, so keep code and comments neutral, concise, and
present-tense, as if written by hand. Match the style of the surrounding code.
