import SwiftUI

/// One-time first-run welcome so a new user knows the path, instead of landing
/// cold on a grid. Shown once (gated by @AppStorage in ContentView).
struct WelcomeSheet: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "wineglass.fill").font(.system(size: 34)).foregroundStyle(DS.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Uncork").font(.system(size: 24, weight: .bold))
                    Text("Play Windows games on your Mac: every store, one place.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                step(1, "checklist", "Check Setup",
                     "Make sure Rosetta is installed; the Setup tab shows what's ready.")
                step(2, "person.badge.key.fill", "Connect a store",
                     "Sign into Steam or Epic on the Stores tab (one time).")
                step(3, "play.circle.fill", "Install & play",
                     "Owned games appear in your Library: install, then hit Play.")
            }

            Text("Tip: each game shows a compatibility badge; green is verified on your Mac, and ProtonDB ratings hint at the rest. Open a game's ⚙ for per-game options.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Button {
                onDone(); dismiss()
            } label: {
                Text("Get started").font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            .background(Capsule().fill(DS.accent))
        }
        .padding(26).frame(width: 480, height: 420)
    }

    private func step(_ n: Int, _ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(DS.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n). \(title)").font(.system(size: 14, weight: .semibold))
                Text(body).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
