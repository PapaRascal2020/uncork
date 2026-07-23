import SwiftUI

/// A game store / launcher WineOnMac can install and run for you (Steam, Epic,
/// EA, GOG …). The hub is the app's home: one place to install, launch, and get
/// setup help for every storefront: the "launcher for launchers".
enum LauncherStatus: String {
    case installed    = "Installed"
    case notInstalled = "Not installed"
    case comingSoon   = "Coming soon"

    var tint: Color {
        switch self {
        case .installed:    return .green
        case .notInstalled: return .secondary
        case .comingSoon:   return .orange
        }
    }
}

struct Launcher: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String          // SF Symbol stand-in for the store logo
    let artStart: Color
    let artEnd: Color
    var status: LauncherStatus
    /// How WineOnMac runs it (shown in the detail/help).
    let runsVia: String
    /// One-line setup note surfaced on the card's info.
    let setupNote: String
    /// "windows" (runs via Wine) or "mac" (native macOS). Shown as a badge.
    var platform: String = "windows"

    var isMac: Bool { platform == "mac" }

    var primaryAction: String {
        switch status {
        case .installed:    return "Launch"
        case .notInstalled: return "Install"
        case .comingSoon:   return "Soon"
        }
    }
    static func == (l: Launcher, r: Launcher) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Launchers {
    /// The storefronts Uncork can set up, data-driven from the store-template
    /// catalog (compat/store-templates.json + user/dev drop-ins), so developers add
    /// a new store by adding a template, no app rebuild. Steam/Epic/GOG ship as
    /// templates; Ubisoft/EA/Origin are intentionally not templates (added via the
    /// Custom Store flow if wanted). See StoreTemplate.swift.
    static var all: [Launcher] { StoreTemplates.shared.all.map { $0.toLauncher() } }

    /// Templates with an automated setup path: the built-in kinds (steam/epic/gog,
    /// each with a setup-<kind>.sh) plus any generic template that ships an installer.
    static var setupableIDs: Set<String> {
        Set(StoreTemplates.shared.all
            .filter { $0.kind != .generic || !$0.installerURL.isEmpty }
            .map { $0.id })
    }
}
