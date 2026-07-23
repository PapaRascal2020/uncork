import SwiftUI
import Foundation

/// A game installed via any store Uncork manages. Steam games come from
/// appmanifest files; Epic games come from legendary.
struct InstalledGame: Identifiable, Hashable, Codable {
    enum Source: String, Codable { case steam = "Steam", epic = "Epic", gog = "GOG", custom = "App" }
    /// Which OS builds a title offers. Windows builds run via Wine; a native Mac
    /// build (GOG/Epic ship them for some titles) runs directly, no engine.
    enum Platform: String, Codable { case windows = "Windows", mac = "Mac" }

    let source: Source
    let launchID: String   // Steam appid / Epic app_name / custom uuid
    let title: String
    let installDir: String // folder name: used to detect the running process
    var installed: Bool = true   // false = owned but not downloaded (installable)
    var coverURL: URL? = nil     // store-provided art (Epic passes it in; Steam derives it)
    var exePath: String? = nil   // custom (non-store) games: host path to the .exe
    var bottle: String? = nil    // custom games: bottle name (per-game name = isolated)
    /// OS builds this title offers. Defaults to Windows (run via Wine); GOG's
    /// worksOn flags add .mac for titles with a native macOS build.
    var platforms: Set<Platform> = [.windows]
    var id: String { "\(source.rawValue):\(launchID)" }

    /// True when this title has a native macOS build (shown in the Library Mac tab
    /// and: once native launch lands: runnable without Wine).
    var hasMac: Bool { platforms.contains(.mac) }
    /// A Windows-via-Wine title (no native Mac build). Most games.
    var isWindowsOnly: Bool { !platforms.contains(.mac) }

    /// The Wine prefix (bottle) this game runs in: the only thing Stop targets.
    /// Steam games share the "steam" bottle; Epic games run in "epic"; custom
    /// games get their own isolated bottle (falling back to "steam").
    var bottleName: String {
        switch source {
        case .steam:  return "steam"
        case .epic:   return "epic"
        case .gog:    return "gog"
        case .custom: return bottle ?? "steam"
        }
    }

    /// Landscape cover art for the grid card. Steam serves it from a public CDN
    /// keyed by appid (no API key); Epic art is supplied by legendary (coverURL).
    /// Falls back to the gradient below when absent or offline.
    var artURL: URL? {
        if let custom = CustomArtStore.shared.coverURL(launchID) { return custom }  // user-set art wins
        switch source {
        case .steam:  return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(launchID)/header.jpg")
        case .epic:   return coverURL
        case .gog:    return coverURL   // GOG cover supplied by gog.sh library
        case .custom: return coverURL   // none by default → gradient fallback
        }
    }

    /// Wide cinematic hero banner for the detail page: Steam's `library_hero`
    /// (the exact art Steam's own game page uses). Others reuse the cover so the
    /// page still gets a banner; gradient fallback when absent/offline.
    var heroURL: URL? {
        if let custom = CustomArtStore.shared.heroURL(launchID) { return custom }  // user-set banner wins
        switch source {
        case .steam: return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(launchID)/library_hero.jpg")
        default:     return coverURL ?? CustomArtStore.shared.coverURL(launchID)
        }
    }

    /// Transparent game logo (Steam's `logo.png`) to sit on the hero, Steam-style.
    /// Steam only; nil elsewhere so we fall back to the title text.
    var logoURL: URL? {
        guard source == .steam else { return nil }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(launchID)/logo.png")
    }

    /// Deterministic artwork gradient from the title: the fallback when no cover.
    var art: (Color, Color) {
        var h = 5381
        for b in title.utf8 { h = ((h << 5) &+ h) &+ Int(b) }
        let hue = Double(abs(h) % 360) / 360.0
        return (Color(hue: hue, saturation: 0.45, brightness: 0.42),
                Color(hue: hue, saturation: 0.55, brightness: 0.16))
    }
}

/// Installed Steam games, read from the bottle's appmanifest_*.acf files.
enum SteamLibrary {
    private static let ignored: Set<String> = ["228980"]  // Steamworks redistributables

    static func scan() -> [InstalledGame] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: Paths.steamApps) else { return [] }
        var games: [InstalledGame] = []
        for f in entries where f.hasPrefix("appmanifest_") && f.hasSuffix(".acf") {
            guard let content = try? String(contentsOfFile: "\(Paths.steamApps)/\(f)", encoding: .utf8),
                  let id = value(content, "appid"), !ignored.contains(id),
                  let name = value(content, "name")
            else { continue }
            games.append(InstalledGame(source: .steam, launchID: id, title: name,
                                       installDir: value(content, "installdir") ?? ""))
        }
        return games
    }

    private static func value(_ content: String, _ key: String) -> String? {
        guard let k = content.range(of: "\"\(key)\"") else { return nil }
        let after = content[k.upperBound...]
        guard let q1 = after.firstIndex(of: "\"") else { return nil }
        let rest = after[after.index(after: q1)...]
        guard let q2 = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<q2])
    }
}

/// Epic games via legendary (scripts/epic.sh): owned + installed status.
enum EpicLibrary {
    /// Map of installed Epic app_name -> install folder name.
    private static func installedDirs() -> [String: String] {
        let json = Shell.run(script: "epic.sh", ["list-installed", "--json"])
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }
        var m: [String: String] = [:]
        for obj in arr {
            if let app = obj["app_name"] as? String {
                m[app] = (((obj["install_path"] as? String) ?? "") as NSString).lastPathComponent
            }
        }
        return m
    }

    /// Every OWNED Epic game, flagged installed or not (nothing if signed out).
    static func scanAll() -> [InstalledGame] {
        guard EpicAuth.isLoggedIn() else { return [] }
        let owned = EpicAuth.ownedGames()
        let dirs = installedDirs()
        return owned.map { g in
            InstalledGame(source: .epic, launchID: g.app, title: g.title,
                          installDir: dirs[g.app] ?? "", installed: dirs[g.app] != nil,
                          coverURL: g.cover.flatMap { URL(string: $0) })
        }
    }
}

/// GOG games via gogdl (scripts/gog.sh): owned library (with cover art from
/// GOG's account API) + installed status (detected from goggame-<id>.info files
/// gogdl writes into the shared "gog" bottle).
enum GogLibrary {
    static func scanAll() -> [InstalledGame] {
        guard GogAuth.isLoggedIn() else { return [] }
        let json = Shell.run(script: "gog.sh", ["library"], report: "load your GOG library")
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        let installed = installedIDs()
        return arr.compactMap { o -> InstalledGame? in
            guard let id = o["id"] as? String, !id.isEmpty else { return nil }
            let title = (o["title"] as? String) ?? id
            let cover = (o["cover"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            let dir = installed[id] ?? ""
            // Platforms from GOG's worksOn flags: always Windows (Wine); + Mac when
            // GOG ships a native macOS build.
            var plats: Set<InstalledGame.Platform> = [.windows]
            if let w = o["worksOn"] as? [String: Any], (w["Mac"] as? Bool) == true { plats.insert(.mac) }
            return InstalledGame(source: .gog, launchID: id, title: title,
                                 installDir: (dir as NSString).lastPathComponent,
                                 installed: !dir.isEmpty, coverURL: cover, platforms: plats)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Map GOG id → install dir from goggame-<id>.info files in the GOG bottle.
    private static func installedIDs() -> [String: String] {
        let root = Paths.data + "/bottles/gog/drive_c/GOG Games"
        let fm = FileManager.default
        guard let games = try? fm.contentsOfDirectory(atPath: root) else { return [:] }
        var m: [String: String] = [:]
        for g in games {
            let dir = root + "/" + g
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasPrefix("goggame-") && f.hasSuffix(".info") {
                let id = f.dropFirst("goggame-".count).dropLast(".info".count)
                m[String(id)] = dir
            }
        }
        return m
    }
}
