import SwiftUI

/// A "runner" is WineOnMac's equivalent of a Proton / GE-Proton version:
/// a self-contained bundle of the Wine build + graphics translation + fixes
/// that a game runs under. Users pick one per game in the Compatibility tab;
/// selecting it re-applies the bundle (the `apply-dxvk.sh` mechanism) and plays.
struct Runner: Identifiable, Hashable {
    let id: String
    let name: String
    let wineBuild: String
    let dxvk: String        // DXVK version, or ", "
    let vkd3d: Bool         // D3D12 via VKD3D-Proton
    let note: String
    let verifiedCount: Int? // crowdsourced "worked for N players", nil if unknown

    var summary: String { "\(wineBuild) · DXVK \(dxvk)\(vkd3d ? " · VKD3D" : "")" }
}

enum Runners {
    /// Curated default: the stable Wine base + our Steam CEF fix + a broadly
    /// compatible DXVK. This is the "just works for most games" option.
    static let ge = Runner(
        id: "ge", name: "WineOnMac-GE",
        wineBuild: "wine-stable 11.0", dxvk: "1.10.3", vkd3d: false,
        note: "Curated default. Steam CEF fix + broad-compatibility DXVK. Best first choice.",
        verifiedCount: 42)

    static let modern = Runner(
        id: "modern", name: "Latest",
        wineBuild: "wine-stable 11.0", dxvk: "3.0.1", vkd3d: false,
        note: "Newest DXVK: best performance on modern (2020+) titles.",
        verifiedCount: nil)

    static let dx12 = Runner(
        id: "dx12", name: "DirectX 12",
        wineBuild: "wine-stable 11.0", dxvk: "3.0.1", vkd3d: true,
        note: "Adds VKD3D-Proton for DirectX 12 games.",
        verifiedCount: nil)

    static let all: [Runner] = [ge, modern, dx12]

    /// The runner the compat DB recommends for a given game (mocked per AppID).
    /// Styx: Shards of Darkness (UE4 4.13) needs the older DXVK: exactly the
    /// kind of per-game knowledge the runner system encodes.
    static func recommended(for appID: Int) -> Runner {
        switch appID {
        case 385510: return ge      // Styx: Shards of Darkness → DXVK 1.10.3
        default:      return ge
        }
    }
}
