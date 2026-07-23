# Uncork

Play Windows games on your Apple Silicon Mac, without the tinkering. Uncork is a
native SwiftUI app that sets up and runs Windows game launchers and games for you,
and gives every store one friendly home: install, launch, and play with no manual
Wine, no command line, and no admin rights.

Open source, Apple Silicon only, for now.

![Uncork library](docs/screenshot.png)

## Status

Work in progress. This is early software: expect rough edges, and some games are
flaky or do not run at all. Each title shows an expected-compatibility badge, but
treat it as a hint, not a guarantee.

Tested on an Apple Silicon (M5) Mac: Euro Truck Simulator 2, Rise of the Tomb
Raider, RISK: Global Domination, Among the Sleep, and Styx.

## What it is

Uncork is a SwiftUI app that drives shell scripts that drive Wine, with a
DirectX-to-Metal translation layer on top. The app is the interface; the engine
work (creating prefixes, installing stores, launching games, applying per-game
fixes) lives in `scripts/` and is data-driven, so most fixes ship as data rather
than a new build.

Where a store or game has a real Mac version, Uncork uses it (for example the
native Battle.net and itch.io clients). Where it does not, Uncork runs the Windows
version through Wine.

## Philosophy

Mac gaming's bottleneck is no longer raw capability. The translation layers (Wine,
DXVK, DXMT, Apple's D3DMetal) are mature. The bottleneck is the journey around them:
prefixes, DLL overrides, winetricks, and the command line. Uncork "macifies" that
journey. It hides the machinery behind a native Mac interface, so playing a Windows
game feels like using any other Mac app: install, press Play, done.

It is not only for Windows games. Uncork is a full game library: it also lists and
launches your native macOS games, and installs native Mac launchers (Battle.net,
itch.io) that run with no Wine at all. The Mac and Windows tabs let you see each.

## Requirements

- Apple Silicon Mac (M1 or newer).
- macOS 14 (Sonoma) or later.
- Xcode command-line tools: `xcode-select --install`
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`
  (the engine runs x86-64 Wine under Rosetta).
- An internet connection for first-run setup and installing your games.

## Building

You can build Uncork two ways.

### From source (a clone)

A clone contains source only. The Wine engines and the graphics backend are large
binaries that are not committed; they are downloaded on first use. The quickest way
to build from a clone is a slim build, which omits the engines and fetches them the
first time they are needed:

```bash
git clone https://github.com/PapaRascal2020/uncork.git
cd uncork
UNCORK_SLIM=1 bash scripts/package-app.sh    # produces build/Uncork.app
```

On first launch the app downloads the graphics engine (and the Steam client, if you
use Steam). Steam, Epic, and GOG work this way out of the box; the CEF-based
launchers (Ubisoft) also need their engine hosted on the project's releases.

### From the build kit

For a fully self-contained build with the engines already included (useful for
testing offline, or on a machine without the downloads), use the build kit:

```bash
tar -xzf uncork-build-kit.tar.gz
cd uncork-build-kit
bash scripts/package-app.sh                  # produces build/Uncork.app
```

`scripts/make-build-kit.sh` produces that kit. Building on the target Mac is also
what keeps code-signing clean: the app is signed on the machine that creates it, so
there is no transfer quarantine from shipping a pre-built `.app`.

Either way, `swift build` inside `app/` is a quick compile check without packaging.

## Repo layout

```
app/          SwiftUI application
scripts/      the engine: bottle setup, store install, launch, fixes
compat/       data-driven databases (game fixes, profiles, store templates)
wine-fixes/   patched-Wine engine recipes, patches, and the Wine build catalog
tools/        small bundled command-line tools
docs/         developer and user guides
```

Large or generated directories (`engine/`, `build/`, `bottles/`, `thirdparty/`,
`dist/`) are not committed; see `.gitignore`.

## Documentation

- `docs/user-guide.html`: the in-app user guide.
- `docs/DEVELOPERS.md` and `docs/developer-guide.html`: how the app is built and how
  to contribute a fix or a new store.

## Contributing

Uncork is free and open source, and built to be extended. Most fixes are data, not
code: a game's compatibility settings live in `compat/gamefixes.json`, and a new
store is a template in `compat/store-templates.json`, so you can fix a game or add a
store without rebuilding the app. Game fixes, store templates, Wine build recipes,
and patches are all welcome. See `docs/DEVELOPERS.md` to get started.

## License

Uncork is licensed under **GPL-3.0** (see `LICENSE`). It bundles and orchestrates
third-party components (Wine, DXVK, DXMT, MoltenVK, and the Epic/GOG command-line
clients), each under its own license, and it downloads Apple's Game Porting Toolkit
at runtime rather than redistributing it. The full component list, licenses, and
upstream sources are in `THIRD-PARTY-NOTICES.md`.
