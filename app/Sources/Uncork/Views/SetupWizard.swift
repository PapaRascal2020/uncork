import SwiftUI

/// First-run setup wizard: Welcome → pick a launcher → Uncork downloads Wine +
/// D3DMetal and sets the store up (verbose) → launch it. Replaces the old static
/// welcome. Keeps Uncork's look; the heavy lifting streams from SetupRunner.
struct SetupWizard: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var runner = SetupRunner.shared
    @ObservedObject private var registry = StoreRegistry.shared

    enum Step { case welcome, pick, install }
    @State private var step: Step = .welcome
    @State private var picked: Launcher?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch step {
            case .welcome: welcome
            case .pick:    picker
            case .install: install
            }
        }
        .padding(26).frame(width: 520, height: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wineglass.fill").font(.system(size: 30)).foregroundStyle(DS.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Uncork").font(.system(size: 22, weight: .bold))
                Text("Play Windows games on your Mac: pick a store and we'll set it up.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uncork installs a tiny Windows compatibility layer (Wine) plus Apple's D3DMetal graphics, automatically, the first time you add a store. No Terminal, no downloads to hunt down.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            featureRow("bolt.fill", "Fast graphics", "Games render through Apple's Metal: the same tech Whisky and CrossOver use.")
            featureRow("shippingbox.fill", "Set up on demand", "We download only what your chosen store needs (~240 MB), the first time.")
            featureRow("gamecontroller.fill", "Your library, your launcher", "Steam, Epic and GOG: sign in once and your games appear in your Library to install and play.")
            Spacer()
            primaryButton("Choose a store") { step = .pick }
        }
    }

    // MARK: Pick a launcher

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which store do you want to set up first?")
                .font(.system(size: 14, weight: .semibold))
            Text("You can add more later from the Stores tab.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(Launchers.all.filter { Launchers.setupableIDs.contains($0.id) }) { l in
                    launcherCard(l)
                }
            }
            Spacer()
            Button("Back") { step = .welcome }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private func launcherCard(_ l: Launcher) -> some View {
        Button { picked = l; step = .install; runner.run(store: l.id) } label: {
            launcherCardBody(l)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func launcherCardBody(_ l: Launcher) -> some View {
        let tile = RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [l.artStart, l.artEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 84)
            .overlay(Image(systemName: l.symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
        VStack(alignment: .leading, spacing: 10) {
            tile
            Text(l.name).font(.system(size: 15, weight: .semibold))
            Text(l.tagline).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2).frame(height: 30, alignment: .top)
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }

    // MARK: Install progress (verbose)

    @ViewBuilder private var install: some View {
        if let p = picked {
            StoreSetupView(
                launcher: p,
                onOpen: { StoreLauncher.open(p); finish() },
                onBack: { runner.reset(); step = .pick }
            )
        }
    }

    // MARK: bits

    private func finish() { onDone(); dismiss() }

    private func featureRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(DS.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(body).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func primaryButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 9)
        }
        .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
    }
}
