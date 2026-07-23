import Foundation
import Combine

/// Caches the library so it loads instantly. An on-disk cache is shown at once on
/// launch, kept in memory across tab switches, and only re-scanned when you hit
/// refresh or a download completes: so the slow part (Epic via legendary) never
/// re-runs just because you revisited the Library tab.
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var games: [InstalledGame] = []
    @Published private(set) var loading = false
    private var loadedThisSession = false
    private let cacheURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheURL = base.appendingPathComponent("library-cache.json")
        if let d = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([InstalledGame].self, from: d) {
            games = cached   // instant first paint from the last session's cache
        }
    }

    /// Called when the Library appears. Scans only the first time this session;
    /// afterwards the in-memory cache is used, so tab switches are instant.
    func loadIfNeeded() {
        guard !loadedThisSession else { return }
        loadedThisSession = true
        refresh()
    }

    /// Force a re-scan (refresh button, or after an install completes).
    func refresh() {
        loadedThisSession = true
        let steam = SteamLibrary.scan()                    // fast: local file reads
        let custom = CustomGamesStore.shared.games()       // instant: user-added exes
        let customStore = CustomStoresStore.shared.games() // instant: custom-store folder scan
        // keep the last network scan's store games visible until the re-scan lands
        let netCached = games.filter { $0.source == .epic || $0.source == .gog }
        games = sorted(steam + custom + customStore + netCached)  // show these at once
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let epic = EpicLibrary.scanAll()               // slow: legendary + network
            let gog = GogLibrary.scanAll()                 // slow: GOG account API
            DispatchQueue.main.async {
                self.games = self.sorted(steam + custom + customStore + epic + gog)
                self.loading = false
                self.save()
            }
        }
    }

    private func sorted(_ list: [InstalledGame]) -> [InstalledGame] {
        list.sorted {
            if $0.installed != $1.installed { return $0.installed && !$1.installed }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(games) { try? d.write(to: cacheURL) }
    }
}
