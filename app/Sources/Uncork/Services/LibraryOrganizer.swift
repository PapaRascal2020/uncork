import Foundation
import Combine

/// User organization of the Library: favorites, hidden games, and custom
/// collections. Keyed by game id (e.g. "Steam:227300"), persisted to
/// library-org.json. Empty collections are pruned automatically, so there's no
/// separate "delete collection" step: remove the last game and it's gone.
final class LibraryOrganizer: ObservableObject {
    static let shared = LibraryOrganizer()

    private struct Stored: Codable {
        var favorites: [String] = []
        var hidden: [String] = []
        var collections: [String: [String]] = [:]
    }

    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var collections: [String: Set<String>] = [:]

    private let url: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("library-org.json")
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stored.self, from: d) {
            favorites = Set(s.favorites)
            hidden = Set(s.hidden)
            collections = s.collections.mapValues(Set.init)
        }
    }

    /// Collection names, alphabetical.
    var collectionNames: [String] { collections.keys.sorted() }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        save()
    }

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }
    func setHidden(_ id: String, _ v: Bool) {
        if v { hidden.insert(id) } else { hidden.remove(id) }
        save()
    }

    func inCollection(_ id: String, _ name: String) -> Bool { collections[name]?.contains(id) ?? false }

    /// Add/remove a game to a collection; a collection that ends up empty is dropped.
    func toggleCollection(_ id: String, _ name: String) {
        var s = collections[name] ?? []
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        collections[name] = s.isEmpty ? nil : s
        save()
    }

    /// Create a collection (if new) and put a game in it.
    func addToCollection(_ id: String, _ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var s = collections[name] ?? []
        s.insert(id)
        collections[name] = s
        save()
    }

    private func save() {
        let s = Stored(favorites: Array(favorites), hidden: Array(hidden),
                       collections: collections.mapValues(Array.init))
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: url) }
    }
}
