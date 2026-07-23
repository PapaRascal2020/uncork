import Foundation
import Combine

/// Tracks per-game playtime + last-played, Steam-style, for the game detail page.
/// Sessions are measured from when RunStore sees a game actually running (window
/// up) to when it exits. Persisted to ~/Library/Application Support/Uncork/playtime.json.
final class PlaytimeStore: ObservableObject {
    static let shared = PlaytimeStore()

    struct Record: Codable { var seconds: Double = 0; var last: Double = 0 }

    @Published private(set) var records: [String: Record] = [:]
    private var sessionStart: [String: Date] = [:]     // game.id -> when it began running
    private let url: URL

    private init() {
        url = URL(fileURLWithPath: Paths.data).appendingPathComponent("playtime.json")
        if let d = try? Data(contentsOf: url),
           let obj = try? JSONDecoder().decode([String: Record].self, from: d) {
            records = obj
        }
    }

    // MARK: session hooks (called by RunStore)

    /// A game's window came up: start timing this session (idempotent).
    func began(_ id: String) {
        if sessionStart[id] == nil { sessionStart[id] = Date() }
    }

    /// A game exited: accumulate the session and stamp last-played.
    func ended(_ id: String) {
        guard let start = sessionStart[id] else { return }
        sessionStart[id] = nil
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 5 else { return }   // ignore instant bounces / false starts
        var r = records[id] ?? Record()
        r.seconds += elapsed
        r.last = Date().timeIntervalSince1970
        records[id] = r
        save()
    }

    // MARK: queries (for the UI)

    func totalSeconds(_ id: String) -> Double { records[id]?.seconds ?? 0 }
    func lastPlayed(_ id: String) -> Date? {
        guard let t = records[id]?.last, t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }
    func hasPlayed(_ id: String) -> Bool { (records[id]?.seconds ?? 0) > 0 }

    /// "3.5 hours" / "42 minutes" / "Never played".
    func playtimeLabel(_ id: String) -> String {
        let s = totalSeconds(id)
        if s < 60 { return "Never played" }
        let mins = Int(s / 60)
        if mins < 60 { return "\(mins) min" }
        let hours = s / 3600
        return String(format: "%.1f hours", hours)
    }

    /// "Today" / "Yesterday" / "3 Jul 2026": nil if never.
    func lastPlayedLabel(_ id: String) -> String? {
        guard let d = lastPlayed(id) else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(records) else { return }
        try? d.write(to: url)
    }
}
