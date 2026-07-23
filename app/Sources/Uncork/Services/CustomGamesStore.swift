import Foundation
import Combine

/// User-added non-store games: any Windows `.exe` (GOG, itch, standalone). They
/// appear in the Library next to Steam/Epic and run through the same DXMT engine.
/// Each can run in its own isolated bottle so its runtimes/tweaks stay contained.
/// Persisted to ~/Library/Application Support/Uncork/custom-games.json.
final class CustomGamesStore: ObservableObject {
    static let shared = CustomGamesStore()

    struct Entry: Codable, Identifiable, Hashable {
        let id: String
        var title: String
        var exePath: String      // Windows: path to .exe. Mac: path to the .app (or native binary).
        var isolated: Bool
        var platform: String?    // "mac" = native macOS app (runs directly, no Wine); nil/"windows" = via Wine
        var isMac: Bool { platform == "mac" }
    }

    @Published private(set) var entries: [Entry] = []
    private let url: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("custom-games.json")
        if let d = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Entry].self, from: d) { entries = list }
    }

    /// As Library items. Windows games: isolated ones get a per-game bottle, others
    /// share "steam" (DXMT-ready). Mac games are native: no bottle, platforms=[.mac],
    /// so they run directly (LaunchService routes them to run-mac.sh, not Wine).
    func games() -> [InstalledGame] {
        entries.map { e in
            InstalledGame(
                source: .custom, launchID: e.id, title: e.title,
                installDir: (e.exePath as NSString).lastPathComponent,  // for run-detection
                installed: true,
                exePath: e.exePath,
                bottle: e.isMac ? nil : (e.isolated ? "custom-\(e.id)" : "steam"),
                platforms: e.isMac ? [.mac] : [.windows])
        }
    }

    /// Add a game. `platform` = "windows" (a .exe run via Wine) or "mac" (a native
    /// .app run directly). `isolated` only matters for Windows games.
    func add(exePath: String, title: String, isolated: Bool, platform: String = "windows") {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.append(Entry(id: id, title: name.isEmpty ? (exePath as NSString).lastPathComponent : name,
                             exePath: exePath, isolated: isolated,
                             platform: platform == "mac" ? "mac" : nil))
        save()
    }

    func remove(id: String) { entries.removeAll { $0.id == id }; save() }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: url) }
    }
}
