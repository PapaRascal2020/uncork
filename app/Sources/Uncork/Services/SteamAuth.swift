import Foundation

/// Detects whether the user has actually signed into Steam in the bottle, so
/// Uncork can show honest status instead of claiming "ready" before sign-in.
enum SteamAuth {
    private static var steamDir: String { Paths.steamDir }

    /// A real sign-in creates userdata/<steamid> (a non-zero numeric folder).
    static func isLoggedIn() -> Bool {
        let ud = steamDir + "/userdata"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: ud) else { return false }
        return entries.contains { $0 != "0" && Int($0) != nil }
    }

    static func accountName() -> String? {
        let vdf = steamDir + "/config/loginusers.vdf"
        guard let c = try? String(contentsOfFile: vdf, encoding: .utf8),
              let k = c.range(of: "\"PersonaName\"") else { return nil }
        let after = c[k.upperBound...]
        guard let q1 = after.firstIndex(of: "\"") else { return nil }
        let rest = after[after.index(after: q1)...]
        guard let q2 = rest.firstIndex(of: "\"") else { return nil }
        let name = String(rest[..<q2])
        return name.isEmpty ? nil : name
    }
}
