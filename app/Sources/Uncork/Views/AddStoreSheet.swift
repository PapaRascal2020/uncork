import SwiftUI

/// "Add a Store": the same setup experience as the first-run wizard: pick a
/// storefront, watch Uncork download the engine + set it up (verbose), then open
/// it. Self-contained (uses SetupRunner + the shared StoreSetupView).
struct AddStoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var registry = StoreRegistry.shared
    @ObservedObject private var runner = SetupRunner.shared
    @State private var installing: Launcher?
    @State private var showCustom = false

    /// Stores with a working automated setup path today. EA is omitted: the EA app
    /// won't install reliably on the Wine engine (its MSI's .NET custom actions
    /// don't run, and it renders a blank page across backends even on CrossOver),
    /// and there's no CLI fallback like Epic's legendary.
    private let setupable: Set<String> = Launchers.setupableIDs

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let l = installing {
                StoreSetupView(launcher: l,
                               onOpen: { StoreLauncher.open(l); dismiss() },
                               onBack: { runner.reset(); installing = nil })
            } else {
                picker
            }
        }
        .padding(22).frame(width: 520, height: 470)
    }

    private var header: some View {
        HStack {
            Image(systemName: installing == nil ? "plus.square.on.square" : "wineglass.fill")
                .font(.system(size: 20)).foregroundStyle(DS.accent)
            Text(installing == nil ? "Add a Store" : "Setting up").font(.system(size: 20, weight: .bold))
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a storefront. Uncork downloads Wine + D3DMetal and sets it up for you, no manual steps.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 10) {
                    if registry.available.isEmpty {
                        Text("Every available store is already set up.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 30)
                    }
                    ForEach(registry.available) { row($0) }
                    customRow
                    importRow
                }
                .padding(.top, 2)
            }
        }
        .sheet(isPresented: $showCustom, onDismiss: { registry.refresh(); dismiss() }) {
            AddCustomStoreSheet(onDone: { registry.refresh() })
        }
    }

    /// Entry to the developer/user-extensible path: add any storefront yourself.
    private var customRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.15)).frame(width: 44, height: 44)
                .overlay(Image(systemName: "plus.rectangle.on.folder").font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom store").font(.system(size: 14, weight: .semibold))
                Text("Add any storefront: Windows (via Wine) or native macOS. You configure it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button { showCustom = true } label: {
                Text("Add…").font(.system(size: 12, weight: .bold)).padding(.vertical, 5).padding(.horizontal, 14)
            }
            .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.secondary.opacity(0.4)))
    }

    /// Run a shared template: import someone's exported recipe; it appears as a
    /// store and sets up a bottle exactly as its author configured it.
    private var importRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.15)).frame(width: 44, height: 44)
                .overlay(Image(systemName: "square.and.arrow.down").font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text("Run a template").font(.system(size: 14, weight: .semibold))
                Text("Import a shared Uncork template (.json): reproduces a store's bottle exactly.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button {
                if TemplateService.importWithPanel() != nil { registry.refresh() }
            } label: {
                Text("Import…").font(.system(size: 12, weight: .bold)).padding(.vertical, 5).padding(.horizontal, 14)
            }
            .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.secondary.opacity(0.4)))
    }

    private func row(_ l: Launcher) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [l.artStart, l.artEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: l.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 2) {
                Text(l.name).font(.system(size: 14, weight: .semibold))
                Text(l.tagline).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if setupable.contains(l.id) {
                Button { installing = l; runner.run(store: l.id) } label: {
                    Text("Set up").font(.system(size: 12, weight: .bold)).padding(.vertical, 5).padding(.horizontal, 14)
                }
                .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
            } else {
                Button { ActivityStore.shared.show("\(l.name) support is coming soon") } label: {
                    Text("Soon").font(.system(size: 12, weight: .semibold)).padding(.vertical, 5).padding(.horizontal, 14)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .background(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.secondary.opacity(0.07)))
    }
}
