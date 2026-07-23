import SwiftUI
import Foundation

/// A plain-language compatibility verdict shown per game, so a launch that
/// won't render is never a surprise. Verdicts come from the protonfixes-for-Mac
/// database (compat/gamefixes.json), the same file scripts/autoconfigure.sh and
/// scripts/play.sh read, so the app, the fixes, and the verdicts never drift,
/// and the DB can be updated without rebuilding the app.
enum GameCompat: String {
    case works        // verified rendering on DXMT/Metal
    case notYet       // launches but needs per-game work (e.g. geometry shaders)
    case unsupported  // won't run (e.g. kernel anti-cheat)
    case untested     // unknown: give it a try

    var label: String {
        switch self {
        case .works:       return "Should work"
        case .notYet:      return "Needs work"
        case .unsupported: return "Unsupported"
        case .untested:    return "Untested"
        }
    }
    var detail: String {
        switch self {
        case .works:       return "Verified on Uncork's DXMT/Metal graphics."
        case .notYet:      return "Launches but not fully working yet, needs a per-game fix."
        case .unsupported: return "Can't run, usually kernel anti-cheat."
        case .untested:    return "Not verified yet, worth a try."
        }
    }
    var tint: Color {
        switch self {
        case .works: return .green; case .notYet: return .orange
        case .unsupported: return .red; case .untested: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .works: return "checkmark.seal.fill"; case .notYet: return "wrench.and.screwdriver.fill"
        case .unsupported: return "xmark.octagon.fill"; case .untested: return "questionmark.circle.fill"
        }
    }

    /// Verdict for a game, from the compat DB (by Steam appid). Unknown -> untested.
    static func of(_ game: InstalledGame) -> GameCompat {
        guard game.source == .steam else { return CompatDB.shared.verdict(forEpic: game.title) }
        return CompatDB.shared.verdict(appid: game.launchID)
    }
}

/// Loads and caches compat/gamefixes.json (the protonfixes-for-Mac DB).
final class CompatDB {
    static let shared = CompatDB()
    private var games: [String: [String: Any]] = [:]
    private var defaultVerdict = "untested"

    private init() { reload() }

    func reload() {
        guard let data = FileManager.default.contents(atPath: Paths.compatDB),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        games = (root["games"] as? [String: [String: Any]]) ?? [:]
        defaultVerdict = ((root["defaults"] as? [String: Any])?["verdict"] as? String) ?? "untested"
    }

    func verdict(appid: String) -> GameCompat {
        let raw = (games[appid]?["verdict"] as? String) ?? defaultVerdict
        return map(raw)
    }
    /// Epic games aren't keyed by appid yet: untested until Epic keys are added.
    func verdict(forEpic title: String) -> GameCompat { .untested }

    /// Optional per-game note (shown in the Compatibility detail).
    func note(appid: String) -> String? { games[appid]?["notes"] as? String }
    /// Preferred launch exe from the DB, if any.
    func launchExe(appid: String) -> String? { games[appid]?["launch_exe"] as? String }
    /// Runtime components (winetricks verbs) this game needs, e.g. ["dotnet40"].
    func winetricks(appid: String) -> [String] { (games[appid]?["winetricks"] as? [String]) ?? [] }

    private func map(_ raw: String) -> GameCompat {
        switch raw {
        case "works":       return .works
        case "needs-work":  return .notYet
        case "unsupported": return .unsupported
        default:            return .untested
        }
    }
}

/// Compact badge used on game cards.
struct GameCompatBadge: View {
    let compat: GameCompat
    var body: some View {
        Label(compat.label, systemImage: compat.symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(compat.tint)
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(Capsule().fill(compat.tint.opacity(0.14)))
    }
}

/// ProtonDB tier styling: a Linux/Proton hint, always labelled as ProtonDB so
/// it's never confused with Uncork's own Metal verdict.
enum ProtonTier {
    static func color(_ t: String) -> Color {
        switch t {
        case "platinum": return Color(red: 0.60, green: 0.85, blue: 0.92)
        case "gold":     return Color(red: 0.92, green: 0.76, blue: 0.30)
        case "silver":   return Color(white: 0.72)
        case "bronze":   return Color(red: 0.82, green: 0.53, blue: 0.34)
        case "borked":   return .red
        default:         return .secondary   // pending / unknown
        }
    }
    static func label(_ t: String) -> String { t.isEmpty ? t : t.prefix(1).uppercased() + t.dropFirst() }
}

struct ProtonBadge: View {
    let tier: String
    var body: some View {
        let c = ProtonTier.color(tier)
        Text("ProtonDB · \(ProtonTier.label(tier))")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(c)
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(Capsule().fill(c.opacity(0.16)))
    }
}

/// The badge shown on a card: our tested Metal verdict wins; if we haven't
/// tested it, fall back to a ProtonDB hint (labelled); else "Untested".
struct CompatIndicator: View {
    let game: InstalledGame
    @ObservedObject private var pdb = ProtonDBStore.shared
    var body: some View {
        let verdict = GameCompat.of(game)
        if verdict != .untested {
            GameCompatBadge(compat: verdict)
        } else if let tier = pdb.tier(for: game) {
            ProtonBadge(tier: tier)
        } else {
            GameCompatBadge(compat: .untested)
        }
    }
}
