# Third-party notices

Uncork is licensed under GPL-3.0 (see `LICENSE`). It orchestrates and, in some
cases, bundles the following third-party components, each under its own license.
Uncork's use does not change those licenses; the copies it distributes remain
governed by the terms below, and their source is available from the linked
upstream projects.

| Component | License | Upstream |
|-----------|---------|----------|
| Wine | LGPL-2.1-or-later | https://gitlab.winehq.org/wine/wine |
| Wine (macOS builds) | LGPL-2.1-or-later | https://github.com/Gcenx/macOS_Wine_builds |
| CrossOver Wine (used by the CEF engine) | LGPL-2.1-or-later | https://github.com/CrossOver-Hack/CrossOver |
| DXVK | Zlib | https://github.com/doitsujin/dxvk |
| DXMT (v0.80) | MIT | https://github.com/3Shain/dxmt |
| MoltenVK | Apache-2.0 | https://github.com/KhronosGroup/MoltenVK |
| winetricks | LGPL-2.1-or-later | https://github.com/Winetricks/winetricks |
| legendary (Epic client) | GPL-3.0 | https://github.com/derrod/legendary |
| gogdl (GOG downloader) | GPL-3.0 | https://github.com/Heroic-Games-Launcher/heroic-gogdl |
| Python (bundled venvs for the above) | PSF License | https://www.python.org |
| steam-on-m1-wine (CEF fix, DXMT recipe) | MIT | https://github.com/ohyicong/steam-on-m1-wine |

Our Wine patches live in `wine-fixes/patches/` and are provided under Wine's
LGPL-2.1-or-later, as derivative works of Wine. The corresponding source for every
LGPL component we distribute is the upstream repository linked above, plus our
patches; a build recipe is in `wine-fixes/`.

## CrossOver and CodeWeavers

Uncork's CEF engine (`wine-cef`, used for the Ubisoft and EA launchers) is built
from CrossOver's Wine sources, which CodeWeavers releases under LGPL-2.1-or-later.
CodeWeavers funds the majority of upstream Wine development. Uncork complies with
the LGPL (corresponding source and these notices) and contributes its fixes back;
see the "Giving back" section of `CONTRIBUTING.md`. If you rely on Uncork, please
consider supporting CodeWeavers by buying CrossOver.

## Not bundled: Apple Game Porting Toolkit (GPTk / D3DMetal)

Uncork does not include, host, or redistribute Apple's Game Porting Toolkit or
D3DMetal. When a game needs the D3DMetal backend, they are downloaded on demand from
the community Gcenx game-porting-toolkit release into a per-user directory. They
remain governed by Apple's own license. Uncork's default DirectX backend is the
open-source DXMT path, which needs nothing from Apple.

## Not bundled: the Steam client

Uncork does not host or redistribute Valve's Steam client. Redistribution is
prohibited by the Steam Subscriber Agreement. Uncork installs Steam from Valve's
official `SteamSetup.exe`, downloaded from Valve's CDN on the user's own machine
(`scripts/setup-steam.sh`).

## Downloaded, not bundled

The default Wine build and the Wine Downloader builds are fetched at runtime from
the Gcenx macOS Wine build releases (https://github.com/Gcenx/macOS_Wine_builds),
under Wine's LGPL-2.1-or-later. Store clients (for example the Steam and Origin
installers) are downloaded from their vendors and remain under their own terms.

## Trademarks and affiliation

Uncork is an independent project. It is **not affiliated with, sponsored by, or
endorsed by** Valve, Epic Games, GOG, Ubisoft, Electronic Arts, Apple, CodeWeavers,
or any other company named here. "Steam", "Epic Games Store", "GOG", "Ubisoft
Connect", "EA app", "macOS", "Metal", and "CrossOver" are trademarks of their
respective owners, used here only to describe compatibility.
