# Decision log

Reasoning behind the locked choices, so future contributors (and future us)
understand the *why*, not just the *what*.

## Platform: Apple Silicon only (for now)

Apple Silicon is where the interesting engineering and the future of the Mac
install base are. Intel Macs avoid the CPU-translation problem entirely (native
x86-64), so they're easier - but a shrinking target. We optimize for the hard,
growing case and can backport Intel support later.

## Graphics: redistributable Proton stack, with optional GPTK

`Game → DXVK/VKD3D-Proton → Vulkan → MoltenVK → Metal`

Every component here is redistributable:

| Component | License |
|-----------|---------|
| Wine | LGPL-2.1+ |
| DXVK | zlib |
| VKD3D-Proton | LGPL-2.1 |
| MoltenVK | Apache-2.0 |

Apple's **GPTK / D3DMetal** (`Game → D3DMetal → Metal`) is often faster but is
**not freely redistributable** - it ships under Apple evaluation/developer
terms. That legal fragility is exactly what put Whisky in an awkward spot. So we
never bundle it: it's an *optional backend the user points us at* from their own
GPTK install. We ship legal by default; power users can opt into more speed.

## Product model: open source, community

Fits the mission. Builds contributors and a shared compatibility database. Any
monetization (donations, optional hosted services) can come later without
compromising the core.

## Wine build (Apple Silicon)

For the MVP we run an **x86-64 Wine build entirely under Rosetta 2** - the whole
stack (Wine + game) is x86, translated by Rosetta. Simpler and fully open; a bit
slower than the GPTK approach (ARM64 Wine + Rosetta only for the game's x86
code). We can adopt the faster split later. The Wine source is configurable via
`WINE_URL` in `scripts/lib.sh`; recommended source is the Gcenx `wine-crossover`
release builds (LGPL, published sources).

## MVP target: We Were Here Together (AppID 865360)

- Unity engine → DirectX 11 → strongest DXVK path
- ProtonDB **Gold** → runs well on the equivalent Linux stack
- No kernel anti-cheat (co-op puzzle, peer networking)
- Devs removed native Linux/Mac builds, so Wine/Proton is the real path - mirrors
  our exact use case

Only added risk vs. Linux: the MoltenVK (Vulkan→Metal) hop, well-trodden for
Unity D3D11 titles.
