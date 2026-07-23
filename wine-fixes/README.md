# Uncork Wine-fixes system

Uncork's analogue of **Proton's patch pipeline + protonfixes** and **CrossOver's
versioned bottles**: a systematic, versioned way to build and track patched Wine
engines and know which engine + fixes each app needs.

**Scope: Mac gaming only.** These engines target game storefronts (Steam, Epic,
GOG, Ubisoft, EA) and games on Apple Silicon, *not* general Windows productivity
apps. That's why the build config is lean (no X11, no Vulkan, minimal programs) and
the patches focus on graphics (DXMT/D3DMetal to Metal) and gaming-launcher (CEF) needs.

## The three layers

1. **Engines**: versioned, patched Wine builds. Catalog: [`engines.json`](engines.json).
   Naming: **`uncork-<uncork-fix-version>-wine-<wine-base-version>`**
   (e.g. `uncork-1.0-wine-11.0` = our patch set 1.0 on a Wine-11 base / CrossOver 26).
   Bump the `uncork` version when the patch set changes; the `wine` version tracks
   the upstream/CrossOver base. `crossover_base` in the catalog pins the exact source.

2. **Patches**: tracked source diffs in [`patches/`](patches/), grouped by purpose:
   - `wine-macos-build/`: make recent Wine build on macOS 26 / Xcode 16+ / clang 21.
   - `winemac-cross-process/`: the winemac.drv IOSurface **consumer** (displays a
     GPU-process-rendered surface in the window-owning process).
   - `dxmt-cross-process/`: the DXMT **producer** (renders CEF's D3D11 into a shared
     IOSurface). Applied to the DXMT tree, not Wine, but versioned here alongside.

3. **App to engine + fixes mapping**: in `compat/profiles.json` (matched engine +
   graphics-backend "profiles", like Proton versions) and `compat/gamefixes.json`
   (per-app: profile/engine + `backend`, `launch_args`, `dll_overrides`, `env`,
   `winetricks`, `verdict`). This is the protonfixes-style per-app fix layer.

## Building an engine

```
wine-fixes/build-engine.sh wine-fixes/recipes/uncork-1.0-wine-11.0.recipe
```

`build-engine.sh` fetches the base source, applies the recipe's patches, configures
(x86_64 native for the Rosetta target), builds (`make -k`, skipping GCC-16-broken
optional programs), installs to `~/wine-cx-build/<engine-id>-root`, and runs the
recipe's `post_build` (graft the DXMT + winemac bridge, codesign). It auto-handles
the known toolchain gotchas (bison PATH, distversion.h, `__ASM_CFI`, `SONAME_LIBVULKAN`).

## Adding a fix / new app

1. **New build/graphics fix**: add a `.patch` under the right `patches/` group,
   list it in the engine's `recipe` + `engines.json`, bump the `uncork` version.
2. **New app**: add an entry to `compat/gamefixes.json` with the engine/profile it
   needs + its `launch_args`/`dll_overrides`/`env`. For CEF launchers, remember the
   Ubisoft-proven flags: `--no-sandbox --disable-direct-composition`,
   `WINEDLLOVERRIDES=d3d11,dxgi,d3d10core=b`, `DXMT_CROSS_PROCESS_PRESENT=1`.

## Current engines (see engines.json for detail)

| Engine | Wine | For | Status |
|---|---|---|---|
| `uncork-1.0-wine-9.0` (wine-cef) | 9.0 / CX24 | **Ubisoft Connect** (32-bit Chromium 135, CEF renders via bridge) | **shipping** |
| `uncork-1.0-wine-11.0` (CX26) | 11.0 / CX26 | EA App (EADesktop runs; blocked on upstream gRPC bug) | experimental |
| `wine-stable` | 11.0 | Steam / Epic / GOG games (DXMT) | shipping (default) |
| `gptk` | 7.7 | D3D12 games (D3DMetal) | downloadable |
