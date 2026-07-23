# Third-party notices

Uncork is licensed under GPL-3.0 (see `LICENSE`). It orchestrates and, in some
cases, bundles the following third-party components, each under its own license.
Uncork's use does not change those licenses; the copies it distributes remain
governed by the terms below, and their source is available from the linked
upstream projects.

| Component | License | Upstream |
|-----------|---------|----------|
| Wine | LGPL-2.1-or-later | https://gitlab.winehq.org/wine/wine |
| DXVK | Zlib | https://github.com/doitsujin/dxvk |
| DXMT (v0.80) | MIT | https://github.com/3Shain/dxmt |
| MoltenVK | Apache-2.0 | https://github.com/KhronosGroup/MoltenVK |
| legendary (Epic client) | GPL-3.0 | https://github.com/derrod/legendary |
| gogdl (GOG downloader) | GPL-3.0 | https://github.com/Heroic-Games-Launcher/heroic-gogdl |
| steam-on-m1-wine (CEF fix, DXMT recipe) | MIT | https://github.com/ohyicong/steam-on-m1-wine |

Our Wine patches live in `wine-fixes/patches/` and are provided under Wine's
LGPL-2.1-or-later, as derivative works of Wine.

## Not bundled: Apple Game Porting Toolkit (GPTk / D3DMetal)

Uncork does not include Apple's Game Porting Toolkit or D3DMetal. It downloads them
on first run into a per-user directory. They remain governed by Apple's own license
and are not redistributed as part of this project.

## Downloaded, not bundled

The default Wine build and the Wine Downloader builds are fetched at runtime from
the Gcenx macOS Wine build releases (https://github.com/Gcenx/macOS_Wine_builds),
under Wine's LGPL-2.1-or-later. Store clients (for example the Origin installer) are
downloaded from their vendors and remain under their own terms.
