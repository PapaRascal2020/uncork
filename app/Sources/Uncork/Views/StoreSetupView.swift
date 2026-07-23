import SwiftUI

/// Marks a store installed and opens its launcher after setup completes.
enum StoreLauncher {
    static func open(_ l: Launcher) {
        StoreRegistry.shared.markInstalled(l.id)
        ActivityStore.shared.show("Opening \(l.name)…")
        switch l.id {
        case "steam": LaunchService.launchSteam()
        case "epic":
            // Epic runs via legendary (no launcher GUI): sign in once. If not yet
            // authorised, open Epic's login so the user can grab the code; the
            // Stores → Epic panel takes the pasted code. If already signed in,
            // nothing to open: the library is already in Uncork.
            if !EpicAuth.isLoggedIn() {
                EpicAuth.openLogin()
                ActivityStore.shared.show("Sign in to Epic in your browser, then paste the code on the Epic panel")
            } else {
                ActivityStore.shared.show("Epic is connected, your library is in Uncork")
            }
        case "origin": LaunchService.launchOrigin()
        case "ubisoft": LaunchService.launchUbisoft()
        case "gog":
            // GOG runs via gogdl (DRM-free, no client GUI): sign in once with a
            // browser code, like Epic. Open GOG's login if not yet authorised.
            if !GogAuth.isLoggedIn() {
                GogAuth.openLogin()
                ActivityStore.shared.show("Sign in to GOG in your browser, then paste the code on the GOG panel")
            } else {
                ActivityStore.shared.show("GOG is connected, your library is in Uncork")
            }
        default:
            // Generic template (Battle.net, developer-added, imported): launch it
            // from its own bottle on the recipe's Wine version.
            if let t = StoreTemplates.shared.template(l.id), t.kind == .generic {
                LaunchService.launchTemplate(t)
            }
        }
    }
}

/// The shared setup panel used by BOTH the first-run wizard and the "Add a Store"
/// sheet, so adding a launcher later looks exactly like the wizard: download the
/// engine → set the store up → open it, with a live bar + verbose log.
struct StoreSetupView: View {
    let launcher: Launcher
    var onOpen: () -> Void = {}
    var onBack: (() -> Void)? = nil
    @ObservedObject private var runner = SetupRunner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setting up \(launcher.name)").font(.system(size: 16, weight: .semibold))

            ProgressView(value: runner.fraction).progressViewStyle(.linear).tint(DS.accent)
            HStack {
                Text(runner.message.isEmpty ? "Working…" : runner.message)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if runner.phase == .running {
                    Text("\(Int(runner.fraction * 100))%").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            }

            // Verbose step-by-step log.
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.logTail.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.75)).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(8)
            }
            .frame(maxWidth: .infinity).frame(height: 130)
            .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.black.opacity(0.18)))

            Spacer(minLength: 0)
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        switch runner.phase {
        case .done:
            Label("\(launcher.name) is ready", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
            primaryButton("Open \(launcher.name)") { onOpen() }
        case .failed:
            Label(runner.message.isEmpty ? "Setup failed" : runner.message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            HStack {
                primaryButton("Try again") { runner.run(store: launcher.id) }
                if let onBack { Button("Back") { onBack() }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
        default:
            Text("First-time setup downloads Wine + D3DMetal, a minute or two. You can keep this open.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func primaryButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 9)
        }
        .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
    }
}
