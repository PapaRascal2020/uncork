import Foundation
import Combine

/// Per-game cloud-save state, persisted to cloud-saves.json: the local save folder
/// (the Wine-prefix path where the game writes its saves) and the last successful
/// sync time. Epic (legendary) usually resolves its own save path from the game's
/// metadata, so the folder is optional there; GOG (gogdl) needs it set. The scripts
/// stay stateless: the app owns this file and passes the values in.
final class CloudSaveStore: ObservableObject {
    static let shared = CloudSaveStore()

    struct Entry: Codable, Hashable {
        var path: String = ""       // local save folder (inside the game's bottle)
        var lastSync: Double = 0    // unix seconds of the last successful sync (0 = never)
    }

    @Published private(set) var entries: [String: Entry] = [:]
    private let url: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("cloud-saves.json")
        if let d = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode([String: Entry].self, from: d) { entries = m }
    }

    func entry(_ id: String) -> Entry { entries[id] ?? Entry() }
    func savePath(_ id: String) -> String { entry(id).path }
    func lastSync(_ id: String) -> Date? {
        let t = entry(id).lastSync
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func setPath(_ id: String, _ path: String) {
        var e = entry(id); e.path = path; entries[id] = e; save()
    }
    func markSynced(_ id: String) {
        var e = entry(id); e.lastSync = Date().timeIntervalSince1970; entries[id] = e; save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: url) }
    }
}
