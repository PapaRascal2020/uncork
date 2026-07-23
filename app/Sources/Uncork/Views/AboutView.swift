import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "wineglass.fill")
                        .font(.system(size: 40)).foregroundStyle(DS.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uncork").font(.system(size: 30, weight: .bold))
                        Text("Play anything on your Mac.").font(.system(size: 14)).foregroundStyle(.secondary)
                        Text("Version 0.1 · open source").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                Text("Uncork runs Windows games on Apple Silicon Macs and gives every storefront one friendly home: install, launch, and play without touching a Windows launcher.")
                    .font(.system(size: 14)).foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                card("What you can do", [
                    ("square.grid.2x2", "Stores", "Set up Steam, Epic and GOG in one click, or add any other store from a template"),
                    ("apple.logo", "Native Mac launchers", "Battle.net and itch.io install as their real macOS apps, no Wine involved"),
                    ("square.stack", "One library", "Every owned game in one grid, filter by Mac or Windows, with per-title compatibility"),
                    ("photo.badge.plus", "Your own artwork", "Set a banner or cover image for any game we can't pull art for"),
                    ("square.and.arrow.up", "Share your setup", "Save a perfected bottle as a template and hand it to someone else"),
                ])

                card("How it works", [
                    ("cpu", "Rosetta 2", "Runs x86-64 game code on Apple Silicon"),
                    ("shippingbox", "Wine", "Translates Windows APIs (no emulation)"),
                    ("square.stack.3d.up", "D3DMetal / DXMT", "Translates DirectX to Metal (per game)"),
                    ("display", "Metal", "Apple's native graphics: the final target"),
                ])

                card("Made to tinker", [
                    ("slider.horizontal.3", "Compatibility profiles", "Pick or download an engine per game, like choosing a Proton version"),
                    ("wrench.and.screwdriver", "Data-driven fixes", "Per-game fixes live in a JSON database, updatable without a new build"),
                    ("chevron.left.forwardslash.chevron.right", "Developer Guide", "See the sidebar: Uncork is open source and built to contribute to"),
                ])

                card("What you need", [
                    ("memorychip", "Apple Silicon", "An M-series Mac (M1 or newer)"),
                    ("macwindow", "macOS 14+", "Sonoma or later"),
                    ("arrow.triangle.2.circlepath", "Rosetta 2", "Installed automatically if missing: the engine runs x86-64 under Rosetta"),
                    ("network", "Internet", "For the first-run setup and installing your games"),
                ])

                card("Built on open source", [
                    ("Wine", "LGPL: the compatibility layer"),
                    ("DXVK", "zlib: Direct3D → Vulkan"),
                    ("DXMT", "Direct3D → Metal (Apple Silicon)"),
                    ("MoltenVK", "Apache-2.0: Vulkan → Metal"),
                    ("Gcenx Wine builds", "The macOS Wine trees in the Wine Downloader"),
                    ("legendary", "GPL-3.0: the Epic Games CLI client"),
                    ("gogdl", "GPL-3.0: the GOG download client"),
                    ("steam-on-m1-wine", "MIT: CEF fix + DXMT build recipe"),
                ].map { ("puzzlepiece.extension", $0.0, $0.1) })

                Text("Uncork bundles only redistributable components, so end users install one app: no admin rights, no developer tools, no manual setup.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .navigationTitle("About")
    }

    private func card(_ title: String, _ rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 16, weight: .semibold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: r.0).foregroundStyle(DS.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.1).font(.system(size: 13, weight: .medium))
                        Text(r.2).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(Color.secondary.opacity(0.08)))
    }
}
