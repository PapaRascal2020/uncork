import SwiftUI
import AppKit

/// Steam-style game page: hero art, playtime stats, a prominent Play/Install, and
/// all the per-game config (compatibility profile, Windows version, performance
/// overlay, components, uninstall). Pushed from the Library grid; everything here
/// is backed by the compat DB + the user-overrides file the engine reads, so
/// changes take effect on the next launch without rebuilding the app.
struct GameDetailView: View {
    let game: InstalledGame
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var run = RunStore.shared
    @ObservedObject private var play = PlaytimeStore.shared
    @ObservedObject private var pdb = ProtonDBStore.shared
    @ObservedObject private var engine = EngineDownloader.shared
    @ObservedObject private var art = CustomArtStore.shared
    @ObservedObject private var cloud = CloudSaveService.shared
    @ObservedObject private var cloudStore = CloudSaveStore.shared
    @ObservedObject private var repair = RepairService.shared

    @State private var profile = "auto"
    @State private var hudOn = false
    @State private var winver = ""
    @State private var launchArgs = ""
    @State private var dllOverrides = ""
    @State private var showAdvanced = false
    @State private var showComponents = false
    @State private var showLog = false
    @State private var confirmRemove = false
    @State private var confirmUninstall = false

    private var compat: GameCompat { GameCompat.of(game) }
    private var note: String? { game.source == .steam ? CompatDB.shared.note(appid: game.launchID) : nil }
    private var antiCheat: String? { game.source == .steam ? CompatDB.shared.anticheat(appid: game.launchID) : nil }
    private var components: [String] { game.source == .steam ? CompatDB.shared.winetricks(appid: game.launchID) : [] }
    private var canUninstall: Bool { (game.source == .epic || game.source == .gog) && game.installed }
    /// Compatibility profiles only drive the Steam launch path (play.sh).
    private var showsProfiles: Bool { game.source == .steam }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 16) {
                    actionRow
                    if showsProfiles { compatibilityCard }
                    else { simpleCompatCard }
                    if let ac = antiCheat { antiCheatCard(ac) }
                    performanceCard
                    if game.source == .steam { advancedCard }
                    if game.source == .steam { componentsCard }
                    if game.source == .steam { steamCloudNote }
                    else if CloudSaveService.supported(game) { cloudSavesCard }
                    dangerZone
                }
                .padding(DS.Space.gutter)
            }
        }
        .navigationTitle(game.title)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                CompatIndicator(game: game)
            }
        }
        .onAppear {
            profile = UserOverrides.shared.profile(game.launchID)
            hudOn = UserOverrides.shared.hud(game.launchID)
            winver = UserOverrides.shared.winver(game.launchID)
            launchArgs = UserOverrides.shared.launchArgs(game.launchID)
            dllOverrides = UserOverrides.shared.dllOverridesString(game.launchID)
        }
        .onChange(of: profile) { _, v in UserOverrides.shared.setProfile(game.launchID, v) }
        .onChange(of: hudOn)   { _, v in UserOverrides.shared.setHUD(game.launchID, v) }
        .onChange(of: winver)  { _, v in UserOverrides.shared.setWinver(game.launchID, v) }
        .onChange(of: launchArgs) { _, v in UserOverrides.shared.setLaunchArgs(game.launchID, v) }
        .onChange(of: dllOverrides) { _, v in UserOverrides.shared.setDLLOverridesString(game.launchID, v) }
        .sheet(isPresented: $showComponents) { WinetricksSheet(game: game) }
        .sheet(isPresented: $showLog) { LogView(game: game) }
    }

    // MARK: hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Wide cinematic banner (Steam's library_hero), or a user-set image.
            LinearGradient(colors: [game.art.0, game.art.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    AsyncImage(url: game.heroURL) { img in img.resizable().scaledToFill() }
                    placeholder: { Color.clear }
                }
                .frame(height: 340).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                .frame(height: 340).allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                // Steam-style: the transparent game logo, falling back to the title.
                if let logo = game.logoURL {
                    AsyncImage(url: logo) { img in
                        img.resizable().scaledToFit().frame(maxWidth: 400, maxHeight: 130, alignment: .bottomLeading)
                            .shadow(radius: 8)
                    } placeholder: { heroTitle }
                } else {
                    heroTitle
                }
                Text("\(game.source.rawValue) · \(game.launchID)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
        }
        .overlay(alignment: .topTrailing) { artworkMenu }
    }

    private var heroTitle: some View {
        Text(game.title).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
            .shadow(radius: 6).lineLimit(2)
    }

    /// Set/replace custom artwork, for games we can't pull art for (or to override
    /// what we did pull). Copies the picked image into Uncork's art store.
    private var artworkMenu: some View {
        Menu {
            Button { pickArt(hero: true) }  label: { Label("Set banner image…", systemImage: "photo") }
            Button { pickArt(hero: false) } label: { Label("Set cover image (grid tile)…", systemImage: "rectangle.on.rectangle") }
            if art.hasArt(game.launchID) {
                Divider()
                Button(role: .destructive) { art.clear(game.launchID) } label: { Label("Reset to default art", systemImage: "arrow.uturn.backward") }
            }
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 13, weight: .semibold))
                .padding(8)
                .background(.black.opacity(0.45), in: Circle())
                .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(14)
        .help("Add or replace this game's artwork")
    }

    private func pickArt(hero: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = hero ? "Choose a banner image for this game" : "Choose a cover image (shown on the Library tile)"
        if panel.runModal() == .OK, let url = panel.url {
            art.set(game.launchID, hero: hero, from: url)
        }
    }

    // MARK: action row (Play/Install + stats)

    private var actionRow: some View {
        HStack(alignment: .center, spacing: 16) {
            if game.installed { PlayButton(game: game) } else { InstallButton(game: game) }
            if run.state(game.id) == .failed {
                Button { LaunchService.applyFixes(game) } label: {
                    Label("Apply fixes", systemImage: "wrench.and.screwdriver.fill")
                        .font(.system(size: 12, weight: .semibold)).padding(.vertical, 6).padding(.horizontal, 12)
                }
                .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(.orange))
            }
            Spacer()
            stat("Playtime", play.playtimeLabel(game.id), "clock")
            if let last = play.lastPlayedLabel(game.id) { stat("Last played", last, "calendar") }
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label(value, systemImage: icon).font(.system(size: 13, weight: .semibold)).labelStyle(.titleAndIcon)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    // MARK: compatibility (with profile picker: Steam)

    private var compatibilityCard: some View {
        card(icon: "checkmark.seal", title: "Compatibility") {
            HStack { GameCompatBadge(compat: compat); Spacer()
                if let tier = pdb.tier(for: game) { ProtonBadge(tier: tier) } }
            Text(compat.detail).font(.system(size: 12)).foregroundStyle(.secondary)
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary.opacity(0.85)) }

            Divider().opacity(0.4)

            // Compatibility profile picker (Steam-style "pick your engine").
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Compatibility profile").font(.system(size: 13, weight: .medium))
                        Text("The engine this game runs on. Change it if the game won't start.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $profile) {
                        ForEach(CompatProfiles.shared.all) { p in Text(p.label).tag(p.id) }
                    }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 220)
                }
                if let p = CompatProfiles.shared.profile(profile) {
                    Text(p.bestFor.isEmpty ? p.summary : p.bestFor)
                        .font(.system(size: 11)).foregroundStyle(.secondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    if let warn = p.warn {
                        Label(warn, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if p.needsDownload && !CompatProfiles.shared.isEngineInstalled(p) {
                        engineDownloadRow(p)
                    }
                }
            }

            Divider().opacity(0.4)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Windows version").font(.system(size: 13, weight: .medium))
                    Text("If a game says your OS is unsupported").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $winver) {
                    Text("Automatic").tag("")
                    Text("Windows 10").tag("win10")
                    Text("Windows 8.1").tag("win81")
                    Text("Windows 7").tag("win7")
                    Text("Windows XP").tag("winxp")
                }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 150)
            }
        }
    }

    // MARK: compatibility (non-Steam: verdict only)

    private var simpleCompatCard: some View {
        card(icon: "checkmark.seal", title: "Compatibility") {
            HStack { GameCompatBadge(compat: compat); Spacer()
                if let tier = pdb.tier(for: game) { ProtonBadge(tier: tier) } }
            Text(compat.detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    /// Download row shown when the selected profile's engine isn't on disk yet
    /// (a downloadable GPTk version): the Steam "install this engine" action.
    @ViewBuilder private func engineDownloadRow(_ p: CompatProfile) -> some View {
        if engine.installing == p.id {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: engine.fraction).tint(DS.accent)
                Text(engine.message).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        } else {
            Button { engine.download(profileID: p.id) { _ in } } label: {
                Label("Download this engine (~240 MB)", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .semibold)).padding(.vertical, 5).padding(.horizontal, 12)
            }
            .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(Color.blue))
            .disabled(engine.isBusy)
        }
    }

    // MARK: advanced (launch args + DLL overrides)

    private var advancedCard: some View {
        card(icon: "terminal", title: "Advanced") {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch options").font(.system(size: 12, weight: .medium))
                        TextField("e.g. -force-d3d11 -windowed", text: $launchArgs)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        Text("Extra command-line arguments passed to the game.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DLL overrides").font(.system(size: 12, weight: .medium))
                        TextField("e.g. d3d11=n;xaudio2_9=b", text: $dllOverrides)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        Text("Wine DLL overrides (name=n native / b builtin), separated by “;”. Power users only.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Launch options & DLL overrides").font(.system(size: 13, weight: .medium))
            }
            .tint(DS.accent)
        }
    }

    private var performanceCard: some View {
        card(icon: "speedometer", title: "Performance") {
            Toggle(isOn: $hudOn) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Performance overlay").font(.system(size: 13, weight: .medium))
                    Text("On-screen FPS & GPU stats while playing").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).tint(DS.accent)
        }
    }

    private var componentsCard: some View {
        card(icon: "shippingbox", title: "Components") {
            if !components.isEmpty {
                HStack {
                    Text("Recommended: \(components.joined(separator: ", "))")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button { LaunchService.installComponents(components, for: game) } label: {
                        Text("Install").font(.system(size: 12, weight: .bold))
                            .padding(.vertical, 5).padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent.opacity(0.85)))
                }
            }
            Button { showComponents = true } label: {
                Label("Manage components (winetricks)…", systemImage: "wrench.adjustable")
                    .font(.system(size: 12, weight: .medium))
            }.buttonStyle(.plain).foregroundStyle(DS.accent)
        }
    }

    private var dangerZone: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { showLog = true } label: {
                    Label("View launch log", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(DS.accent).background(Capsule().fill(DS.accent.opacity(0.12)))
                .help("See what happened on the last launch (the game's own output and Uncork's steps). Useful when a game won't start")

                if game.installed {
                    let busy = run.state(game.id) == .launching || run.state(game.id) == .running
                    Button { run.launch(game, diagnostic: true) } label: {
                        Label("Relaunch with diagnostics", systemImage: "stethoscope")
                            .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain).foregroundStyle(DS.accent)
                    .background(Capsule().fill(DS.accent.opacity(busy ? 0.05 : 0.12)))
                    .disabled(busy)
                    .help("Launch again with extra Wine logging turned on, then open the log. Use this when the normal log doesn't show why a game fails")
                }
            }
            if game.source == .steam {
                Button { LaunchService.applyFixes(game) } label: {
                    Label("Apply fixes from database", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(DS.accent).background(Capsule().fill(DS.accent.opacity(0.12)))
                .help("Re-run every fix this game needs (system cleanup, runtimes). Use this if it won't launch")
            }
            if RepairService.supported(game) {
                let busy = repair.state(for: game.id) == .running
                Button { repair.repair(game) } label: {
                    Label(busy ? "Verifying & repairing…" : "Verify & repair",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(DS.accent)
                .background(Capsule().fill(DS.accent.opacity(busy ? 0.05 : 0.12)))
                .disabled(busy)
                .help("Re-check this game's files and re-download anything missing or corrupt")
            }
            if canUninstall {
                Button { confirmUninstall = true } label: {
                    Label("Uninstall", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(.red).background(Capsule().fill(.red.opacity(0.12)))
                .confirmationDialog("Uninstall “\(game.title)”?", isPresented: $confirmUninstall, titleVisibility: .visible) {
                    Button("Uninstall", role: .destructive) { LaunchService.uninstall(game); dismiss() }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This deletes the downloaded game files. You can reinstall it anytime from your library.") }
            }
            if game.source == .custom {
                Button { confirmRemove = true } label: {
                    Label("Remove from Library", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(.red).background(Capsule().fill(.red.opacity(0.12)))
                .confirmationDialog("Remove “\(game.title)” from your Library?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        CustomGamesStore.shared.remove(id: game.launchID); LibraryStore.shared.refresh(); dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This only removes it from Uncork: the game files on disk aren't deleted.") }
            }
        }
        .padding(.top, 4)
    }

    /// A hard-limit warning for anti-cheat titles: EAC/BattlEye have no macOS
    /// runtime, so nothing Uncork does can make them run. Red so it's not mistaken
    /// for a fixable compatibility note.
    private func antiCheatCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.red)
                Text("Anti-cheat").font(.system(size: 14, weight: .semibold))
            }
            Text("This game uses \(name), which has no macOS version, so it can't run on Apple Silicon (online play won't start). This is a hard limit of the anti-cheat, not a graphics or Wine problem, so there's no fix from Uncork.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.red.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).strokeBorder(Color.red.opacity(0.25)))
    }

    /// Steam saves are handled by Steam Cloud in the client, not by Uncork.
    private var steamCloudNote: some View {
        card(icon: "icloud", title: "Cloud saves") {
            Text("Steam saves sync automatically through Steam Cloud in the Steam client, so Uncork does not manage them separately.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Epic/GOG cloud saves: sync two-way, or force upload/download, with the save
    /// folder GOG needs (Epic auto-resolves it, but an override is allowed).
    private var cloudSavesCard: some View {
        let id = game.id
        let sp = cloudStore.savePath(id)
        let syncing = cloud.state(for: id) == .syncing
        let needsFolder = game.source == .gog && sp.isEmpty
        return card(icon: "icloud", title: "Cloud saves") {
            VStack(alignment: .leading, spacing: 10) {
                Text(game.source == .gog
                     ? "Sync your GOG saves to the cloud. Set the folder where this game keeps its saves, then sync."
                     : "Sync your Epic saves to the cloud.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(sp.isEmpty ? "Save folder not set" : (sp as NSString).lastPathComponent)
                        .font(.system(size: 11)).foregroundStyle(needsFolder ? .orange : .secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(sp.isEmpty ? "Choose…" : "Change…") { pickSaveFolder() }.controlSize(.small)
                    if !sp.isEmpty {
                        Button { cloudStore.setPath(id, "") } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button { cloud.sync(game, mode: .auto) } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .semibold)).padding(.vertical, 5).padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .background(Capsule().fill(DS.accent.opacity(syncing || needsFolder ? 0.4 : 1)))
                    .disabled(syncing || needsFolder)

                    Menu {
                        Button { cloud.sync(game, mode: .up) }   label: { Label("Upload to cloud", systemImage: "arrow.up") }
                        Button { cloud.sync(game, mode: .down) } label: { Label("Download from cloud", systemImage: "arrow.down") }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .disabled(syncing || needsFolder)

                    Spacer()
                    if syncing { ProgressView().controlSize(.small) }
                }

                if let m = cloud.message(for: id), !m.isEmpty {
                    Text(m).font(.system(size: 11))
                        .foregroundStyle(cloud.state(for: id) == .failed ? .orange : .secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                } else if let d = cloudStore.lastSync(id) {
                    Text("Last synced \(d.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Pick the folder (inside the game's bottle) where it writes saves; gogdl/
    /// legendary sync exactly this directory with the cloud.
    private func pickSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose the folder where \(game.title) stores its saves (inside its Wine drive_c)"
        let root = Paths.data + "/bottles/\(game.bottleName)/drive_c"
        if FileManager.default.fileExists(atPath: root) { panel.directoryURL = URL(fileURLWithPath: root) }
        if panel.runModal() == .OK, let u = panel.url { cloudStore.setPath(game.id, u.path) }
    }

    @ViewBuilder private func card<Content: View>(icon: String, title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(DS.accent)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.secondary.opacity(0.10)))
    }
}
