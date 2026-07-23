import Foundation
import AppKit
import Combine

/// User-supplied artwork per game, for titles Uncork can't pull art for (Epic/GOG
/// without covers, custom .exe/.app, or a Steam game missing CDN art). The picked
/// image is copied into <UNCORK_DATA>/art/ so it survives even if the original
/// moves, and referenced by a unique filename so AsyncImage always reloads the
/// fresh image (no stale cache when you replace it). Keyed by the game's launchID.
final class CustomArtStore: ObservableObject {
    static let shared = CustomArtStore()

    struct Art: Codable, Hashable { var cover: String?; var hero: String? }

    @Published private(set) var map: [String: Art] = [:]
    private let jsonURL: URL
    private let dir: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        dir = base.appendingPathComponent("art", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        jsonURL = base.appendingPathComponent("custom-art.json")
        if let d = try? Data(contentsOf: jsonURL),
           let m = try? JSONDecoder().decode([String: Art].self, from: d) { map = m }
    }

    func coverURL(_ id: String) -> URL? { map[id]?.cover.map { URL(fileURLWithPath: $0) } }
    func heroURL(_ id: String)  -> URL? { map[id]?.hero.map  { URL(fileURLWithPath: $0) } }
    func hasArt(_ id: String) -> Bool { map[id]?.cover != nil || map[id]?.hero != nil }

    /// Copy `src` into our art dir under a unique name and record it as this game's
    /// cover (grid tile) or hero (detail banner). Returns false if the copy fails.
    @discardableResult
    func set(_ id: String, hero: Bool, from src: URL) -> Bool {
        let ext = src.pathExtension.isEmpty ? "png" : src.pathExtension
        let dest = dir.appendingPathComponent("\(id)-\(hero ? "hero" : "cover")-\(UUID().uuidString.prefix(8)).\(ext)")
        do {
            let data = try Data(contentsOf: src)
            try data.write(to: dest)
        } catch { return false }
        var art = map[id] ?? Art()
        // Delete the previous file we owned so the art dir doesn't accumulate.
        let old = hero ? art.hero : art.cover
        if let old { try? FileManager.default.removeItem(atPath: old) }
        if hero { art.hero = dest.path } else { art.cover = dest.path }
        map[id] = art; save()
        return true
    }

    /// Drop all custom art for a game (fall back to CDN / gradient).
    func clear(_ id: String) {
        if let a = map[id] {
            [a.cover, a.hero].compactMap { $0 }.forEach { try? FileManager.default.removeItem(atPath: $0) }
        }
        map[id] = nil; save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(map) { try? d.write(to: jsonURL) }
    }
}
