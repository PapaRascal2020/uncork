import Foundation
import AppKit

/// In-app Epic sign-in via legendary's authorization-code flow: open Epic's
/// login in the browser, the user copies the `authorizationCode` shown on the
/// redirect page, pastes it back into Uncork, and we hand it to legendary.
enum EpicAuth {
    /// Epic login page with legendary's redirect: forces sign-in first, then
    /// bounces to the page that shows the authorizationCode. (Hitting the bare
    /// redirect endpoint returns a null code when you're not already logged in.)
    static let loginURL = URL(string:
        "https://www.epicgames.com/id/login?redirectUrl=https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3FclientId%3D34a02cf8f4414e29b15921876da36f9a%26responseType%3Dcode")!

    static func isLoggedIn() -> Bool {
        let s = Shell.run(script: "epic.sh", ["status"])
        return s.contains("Epic account:") && !s.contains("<not logged in>")
    }

    static func accountName() -> String? {
        let s = Shell.run(script: "epic.sh", ["status"])
        guard let line = s.split(separator: "\n").first(where: { $0.contains("Epic account:") }) else { return nil }
        let name = line.replacingOccurrences(of: "Epic account:", with: "").trimmingCharacters(in: .whitespaces)
        return (name.isEmpty || name.contains("not logged in")) ? nil : name
    }

    static func openLogin() { NSWorkspace.shared.open(loginURL) }

    /// Exchange the pasted authorization code for a session. Returns success.
    static func authorize(code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        _ = Shell.run(script: "epic.sh", ["auth", "--code", trimmed])
        return isLoggedIn()
    }

    struct OwnedGame: Identifiable, Hashable {
        let app: String; let title: String
        var cover: String? = nil   // landscape key-image URL from Epic metadata
        var id: String { app }
    }

    /// The games this account owns on Epic (installed or not).
    static func ownedGames() -> [OwnedGame] {
        let json = Shell.run(script: "epic.sh", ["list-games", "--json"], report: "load your Epic library")
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { obj -> OwnedGame? in
            guard let app = obj["app_name"] as? String else { return nil }
            // Keep only actual games: Epic also returns UE plugins/assets
            // (e.g. "Photon Cloud"), which carry plugin/asset categories, not "games".
            let md = obj["metadata"] as? [String: Any]
            let cats = (md?["categories"] as? [[String: Any]])?.compactMap { $0["path"] as? String } ?? []
            guard cats.contains("games") else { return nil }
            let title = (obj["app_title"] as? String) ?? (obj["title"] as? String) ?? app
            // Pick a landscape cover from Epic's keyImages (to match the card),
            // preferring wide art; fall back through to whatever exists.
            let keyImages = (md?["keyImages"] as? [[String: Any]]) ?? []
            let preferred = ["DieselGameBox", "OfferImageWide", "DieselGameBoxWide",
                             "DieselStoreFrontWide", "Featured", "Thumbnail", "DieselGameBoxTall"]
            let cover = preferred.lazy.compactMap { type in
                keyImages.first { ($0["type"] as? String) == type }?["url"] as? String
            }.first
            return OwnedGame(app: app, title: title, cover: cover)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func installedAppNames() -> Set<String> {
        let json = Shell.run(script: "epic.sh", ["list-installed", "--json"])
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return Set(arr.compactMap { $0["app_name"] as? String })
    }

    /// Kick off a (potentially large) background download+install of an Epic game.
    static func install(app: String) {
        DispatchQueue.global(qos: .utility).async {
            _ = Shell.run(script: "epic.sh", ["install", app, "--yes", "--skip-sdl"])
        }
    }
}
