import SwiftUI

/// Wine Manager: the Heroic-style "engines" screen. Lists every compatibility
/// engine (matched Wine + graphics backend, our analog of Proton versions), shows
/// which are built in vs downloadable, and lets the user fetch/remove them. These
/// are the same engines the per-game and per-launcher compat pickers choose from
/// (compat/profiles.json → CompatProfiles; downloads via ensure-profile.sh →
/// EngineDownloader), so managing them here updates the whole app, no rebuild.
struct WineManagerView: View {
    enum Tab: String, CaseIterable, Identifiable { case engines = "Engines", builds = "Wine Builds"; var id: String { rawValue } }

    @ObservedObject private var dl = EngineDownloader.shared
    @ObservedObject private var wb = WineBuildInstaller.shared
    @State private var tab: Tab = .engines
    @State private var profiles: [CompatProfile] = CompatProfiles.shared.all
    @State private var builds: [WineBuild] = WineBuildsCatalog.shared.all
    @State private var installed: Set<String> = []       // engineIDs present on disk
    @State private var installedBuilds: Set<String> = []  // wine-build ids present on disk

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, DS.Space.gutter)

                switch tab {
                case .engines:
                    LazyVStack(spacing: 12) { ForEach(profiles) { p in engineCard(p) } }
                        .padding(.horizontal, DS.Space.gutter)
                    footer
                case .builds:
                    LazyVStack(spacing: 12) { ForEach(builds) { b in buildCard(b) } }
                        .padding(.horizontal, DS.Space.gutter)
                    buildsFooter
                }
            }
            .padding(.vertical, DS.Space.gutter)
        }
        .navigationTitle("Wine Downloader")
        .onAppear(perform: refresh)
        .onChange(of: dl.installing) { if dl.installing.isEmpty { refresh() } }  // refresh when a download ends
        .onChange(of: wb.installing) { if wb.installing.isEmpty { refresh() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Engines").font(.system(size: 20, weight: .bold))
            Text("Matched Wine + graphics backends: the Mac equivalent of Proton versions. Pick one per game or launcher in its Compatibility panel; download extra engines here.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.gutter)
    }

    @ViewBuilder private func engineCard(_ p: CompatProfile) -> some View {
        let isInstalled = p.engineID.isEmpty || p.bundled || installed.contains(p.engineID)
        let isDownloadingThis = dl.installing == p.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(p.label).font(.system(size: 15, weight: .semibold))
                        if !p.backend.isEmpty { backendPill(p.backend) }
                        if p.id == CompatProfiles.shared.defaultID { defaultPill }
                    }
                    Text(p.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !p.bestFor.isEmpty {
                        Text("Best for: \(p.bestFor)").font(.system(size: 11)).foregroundStyle(.secondary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                statusColumn(p, isInstalled: isInstalled, isDownloadingThis: isDownloadingThis)
            }
            if let warn = p.warn {
                Label(warn, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if isDownloadingThis {
                ProgressView(value: dl.fraction).progressViewStyle(.linear).tint(DS.accent)
                Text(dl.message.isEmpty ? "Downloading…" : dl.message)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    @ViewBuilder private func statusColumn(_ p: CompatProfile, isInstalled: Bool, isDownloadingThis: Bool) -> some View {
        if isInstalled {
            Label(p.bundled || p.engineID.isEmpty ? "Built in" : "Installed", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green).labelStyle(.titleAndIcon)
        } else if isDownloadingThis {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("\(Int(dl.fraction * 100))%").font(.system(size: 11)) }
        } else {
            Button {
                EngineDownloader.shared.download(profileID: p.id) { ok in
                    ActivityStore.shared.show(ok ? "\(p.label) downloaded" : "Couldn't download \(p.label)")
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.system(size: 12, weight: .semibold)).padding(.vertical, 5).padding(.horizontal, 12)
            }
            .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
            .disabled(dl.isBusy)
        }
    }

    private func backendPill(_ backend: String) -> some View {
        Text(backend.uppercased()).font(.system(size: 9, weight: .bold))
            .padding(.vertical, 2).padding(.horizontal, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.18))).foregroundStyle(.secondary)
    }
    private var defaultPill: some View {
        Text("DEFAULT").font(.system(size: 9, weight: .bold))
            .padding(.vertical, 2).padding(.horizontal, 6)
            .background(Capsule().fill(DS.accent.opacity(0.2))).foregroundStyle(DS.accent)
    }

    private var footer: some View {
        Text("Engines download on demand into your app data and are shared by all games. Assign one to a specific game or launcher from its Compatibility panel.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, DS.Space.gutter).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Wine Builds tab

    @ViewBuilder private func buildCard(_ b: WineBuild) -> some View {
        let isInstalled = installedBuilds.contains(b.id)
        let isDownloadingThis = wb.installing == b.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(b.name) \(b.version)").font(.system(size: 15, weight: .semibold))
                        channelPill(b.channel)
                        if b.dxmt { tagPill("DXMT") }
                    }
                    Text(b.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !b.notes.isEmpty {
                        Text(b.notes).font(.system(size: 11)).foregroundStyle(.secondary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                if isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                } else if isDownloadingThis {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("\(Int(wb.fraction * 100))%").font(.system(size: 11)) }
                } else {
                    Button {
                        WineBuildInstaller.shared.download(buildID: b.id) { ok in
                            ActivityStore.shared.show(ok ? "\(b.name) \(b.version) installed" : "Couldn't download \(b.name)")
                        }
                    } label: {
                        Label(b.sizeMB > 0 ? "Get (\(b.sizeMB) MB)" : "Get", systemImage: "arrow.down.circle")
                            .font(.system(size: 12, weight: .semibold)).padding(.vertical, 5).padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
                    .disabled(wb.isBusy)
                }
            }
            if isDownloadingThis {
                ProgressView(value: wb.fraction).progressViewStyle(.linear).tint(DS.accent)
                Text(wb.message.isEmpty ? "Downloading…" : wb.message).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    private func channelPill(_ ch: String) -> some View {
        tagPill(ch.uppercased())
    }
    private func tagPill(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .bold))
            .padding(.vertical, 2).padding(.horizontal, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.18))).foregroundStyle(.secondary)
    }

    private var buildsFooter: some View {
        Text("Standalone Wine runtimes (Gcenx macOS builds, DXMT baked in) for trialling a game/launcher on a different Wine when it misbehaves. Downloaded into your app data.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, DS.Space.gutter).fixedSize(horizontal: false, vertical: true)
    }

    private func refresh() {
        profiles = CompatProfiles.shared.all
        builds = WineBuildsCatalog.shared.all
        DispatchQueue.global(qos: .userInitiated).async {
            let inst = Set(CompatProfiles.shared.all.filter { !$0.engineID.isEmpty && CompatProfiles.shared.isEngineInstalled($0) }.map { $0.engineID })
            let instB = Set(WineBuildsCatalog.shared.all.filter { WineBuildsCatalog.shared.isInstalled($0) }.map { $0.id })
            DispatchQueue.main.async { installed = inst; installedBuilds = instB }
        }
    }
}
