import Foundation

/// The per-game launch log. The launch scripts write their narration and the game
/// process's own output here (path passed in as UNCORK_GAME_LOG), so a failed or
/// misbehaving launch can be inspected instead of vanishing into /dev/null.
enum GameLog {
    /// One file per game under the writable data dir; the id is sanitised so ':'
    /// and '/' don't break the path. This exact path is handed to the scripts.
    static func path(for game: InstalledGame) -> String {
        let safe = game.id
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return Paths.data + "/logs/\(safe).log"
    }

    static func exists(_ game: InstalledGame) -> Bool {
        FileManager.default.fileExists(atPath: path(for: game))
    }

    static func read(_ game: InstalledGame) -> String? {
        try? String(contentsOfFile: path(for: game), encoding: .utf8)
    }
}
