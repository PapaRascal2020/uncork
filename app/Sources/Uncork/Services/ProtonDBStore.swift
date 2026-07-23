import Foundation
import Combine

/// ProtonDB tiers, shown as a hint: it's Linux/Proton (Vulkan) data, not the
/// Metal verdict (a Proton-Platinum game can still need work on Metal). Steam
/// games map by appid; Epic games resolve to a Steam appid via an exact name
/// match only (never a fuzzy guess that could show the wrong game's rating).
/// Results are cached to disk and fetched once, throttled to avoid hammering.
final class ProtonDBStore: ObservableObject {
    static let shared = ProtonDBStore()

    // game.id -> tier ("none" = looked up, nothing found). Published so cards refresh.
    @Published private(set) var tiers: [String: String] = [:]
    private var appidByKey: [String: String] = [:]   // game.id -> steam appid ("none")
    private var inflight = Set<String>()
    private let queue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 4; q.qualityOfService = .utility; return q
    }()
    private let cacheURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheURL = base.appendingPathComponent("protondb-cache.json")
        if let d = try? Data(contentsOf: cacheURL),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: [String: String]] {
            tiers = obj["tiers"] ?? [:]
            appidByKey = obj["appids"] ?? [:]
        }
    }

    /// Cached tier for a game, or nil. Kicks a one-time background lookup if unknown.
    func tier(for game: InstalledGame) -> String? {
        if let t = tiers[game.id] { return t == "none" ? nil : t }
        lookup(game)
        return nil
    }

    private func lookup(_ game: InstalledGame) {
        guard !inflight.contains(game.id) else { return }
        inflight.insert(game.id)
        queue.addOperation { [weak self] in
            guard let self else { return }
            let appid = self.resolveAppid(game)
            let tier = (appid != nil && appid != "none") ? (self.fetchTier(appid!) ?? "none") : "none"
            DispatchQueue.main.async {
                self.tiers[game.id] = tier
                self.inflight.remove(game.id)
                self.save()
            }
        }
    }

    // MARK: - resolution

    private func resolveAppid(_ game: InstalledGame) -> String? {
        if game.source == .steam { return game.launchID }
        if let cached = appidByKey[game.id] { return cached }
        let appid = steamAppidExact(for: game.title) ?? "none"
        DispatchQueue.main.async { self.appidByKey[game.id] = appid }
        return appid
    }

    /// Steam storefront search, accepting only an exact (normalised) name match.
    private func steamAppidExact(for title: String) -> String? {
        guard let term = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://store.steampowered.com/api/storesearch/?term=\(term)&l=en&cc=US"),
              let data = syncGET(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return nil }
        let want = Self.norm(title)
        for it in items {
            if let name = it["name"] as? String, Self.norm(name) == want {
                if let id = it["id"] as? Int { return String(id) }
                if let id = it["id"] as? String { return id }
            }
        }
        return nil
    }

    private func fetchTier(_ appid: String) -> String? {
        guard let url = URL(string: "https://www.protondb.com/api/v1/reports/summaries/\(appid).json"),
              let data = syncGET(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tier = root["tier"] as? String, !tier.isEmpty else { return nil }
        return tier
    }

    // MARK: - helpers

    private static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func syncGET(_ url: URL) -> Data? {
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        var req = URLRequest(url: url); req.timeoutInterval = 12
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { out = d }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 14)
        return out
    }

    private func save() {
        let obj: [String: [String: String]] = ["tiers": tiers, "appids": appidByKey]
        if let d = try? JSONSerialization.data(withJSONObject: obj) { try? d.write(to: cacheURL) }
    }
}
