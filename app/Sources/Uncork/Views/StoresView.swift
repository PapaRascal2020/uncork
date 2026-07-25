import SwiftUI
import AppKit

/// The home screen: a hub of game stores/launchers.
struct StoresView: View {
    @ObservedObject private var registry = StoreRegistry.shared
    @ObservedObject private var customStores = CustomStoresStore.shared
    @State private var selected: Launcher?
    @State private var showAddStore = false
    @State private var epicConnected = false
    @State private var steamConnected = false
    @State private var gogConnected = false
    @State private var loaded = false   // false until the first sign-in check resolves
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(registry.installed.isEmpty
                     ? "No stores yet, add one to start playing"
                     : "Your game stores, one place")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Space.gutter).padding(.top, 4)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(registry.installed) { launcher in
                        LauncherCard(launcher: launcher, connected: connected(for: launcher.id),
                                     loading: !loaded, onOpen: { selected = launcher },
                                     onRemove: { registry.uninstall(launcher.id) },
                                     onInstallLocation: InstallLocationService.supports(launcher.id)
                                         ? { pickInstallLocation(launcher.id) } : nil)
                            .contextMenu {
                                Button(role: .destructive) {
                                    registry.uninstall(launcher.id)
                                } label: { Label("Remove \(launcher.name)", systemImage: "trash") }
                            }
                    }
                    // User-added custom stores (Windows via Wine or native macOS).
                    ForEach(customStores.launchers()) { launcher in
                        LauncherCard(launcher: launcher, loading: false, onOpen: { selected = launcher },
                                     onRemove: {
                                        if let e = customStores.entry(forLauncherID: launcher.id) { customStores.remove(id: e.id) }
                                     })
                            .contextMenu {
                                Button(role: .destructive) {
                                    if let e = customStores.entry(forLauncherID: launcher.id) { customStores.remove(id: e.id) }
                                } label: { Label("Remove \(launcher.name)", systemImage: "trash") }
                            }
                    }
                    AddStoreCard { showAddStore = true }
                }
                .padding(DS.Space.gutter)
            }
        }
        .navigationTitle("Stores")
        .onAppear(perform: refresh)
        .sheet(item: $selected, onDismiss: refresh) { launcher in
            switch launcher.id {
            case "epic":  EpicSetupSheet()
            case "steam": SteamSetupSheet()
            case "gog":   GogSetupSheet()
            default:      LauncherHelpSheet(launcher: launcher)
            }
        }
        .sheet(isPresented: $showAddStore, onDismiss: refresh) {
            AddStoreSheet()   // self-contained wizard-style setup (download → set up → open)
        }
    }

    private func connected(for id: String) -> Bool? {
        switch id {
        case "epic": return epicConnected
        case "steam": return steamConnected
        case "gog": return gogConnected
        default: return nil
        }
    }

    /// Choose the folder where a store's games download; the service moves any
    /// existing games there and symlinks the store's install root to it.
    private func pickInstallLocation(_ id: String) {
        let svc = InstallLocationService.shared
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose where \(id.capitalized) games download. Games already installed move here."
        let cur = svc.current(store: id)
        if !cur.isEmpty, FileManager.default.fileExists(atPath: cur) { panel.directoryURL = URL(fileURLWithPath: cur) }
        if panel.runModal() == .OK, let url = panel.url { svc.set(store: id, path: url.path) }
    }

    private func refresh() {
        registry.refresh()
        DispatchQueue.global(qos: .userInitiated).async {
            let e = EpicAuth.isLoggedIn(); let s = SteamAuth.isLoggedIn(); let g = GogAuth.isLoggedIn()
            DispatchQueue.main.async { epicConnected = e; steamConnected = s; gogConnected = g; loaded = true }
        }
    }
}

/// The dashed "＋ Add a Store" tile that sits after the installed store cards.
struct AddStoreCard: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundStyle(DS.accent)
                Text("Add a Store").font(.system(size: 14, weight: .semibold))
                Text("Install Steam, Epic and more").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).frame(height: 176)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.secondary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

struct LauncherCard: View {
    let launcher: Launcher
    var connected: Bool? = nil
    var loading: Bool = false
    /// Whether the store's bottle is present on disk. For non-auth stores (e.g.
    /// Ubisoft Connect) this decides Launch vs Install: the card is otherwise
    /// only shown in the installed grid, so it's normally true.
    var installed: Bool = true
    var onOpen: () -> Void = {}
    /// Remove this store (delete its bottle / native app / forget it). Shown in the
    /// card's overflow menu so removal is discoverable, not hidden.
    var onRemove: (() -> Void)? = nil
    /// Choose where this store's games download (Epic/GOG). nil = not offered.
    var onInstallLocation: (() -> Void)? = nil

    // connected == nil → store has no sign-in (use install state).
    // connected == true → signed in.  connected == false → sign-in needed.
    private var isAuthStore: Bool { connected != nil }
    private var isConnected: Bool { connected == true }

    private var statusText: String {
        if !isAuthStore { return installed ? "Installed" : launcher.status.rawValue }
        return isConnected ? "Signed in" : "Sign-in needed"
    }
    private var statusTint: Color {
        if !isAuthStore { return installed ? .green : launcher.status.tint }
        return isConnected ? .green : .orange
    }
    private var statusIcon: String {
        if !isAuthStore { return installed ? "checkmark.circle.fill" : "arrow.down.circle" }
        return isConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark"
    }
    private var actionTitle: String {
        if !isAuthStore { return installed ? "Launch" : launcher.primaryAction }
        if !isConnected { return "Sign in" }
        return launcher.id == "steam" ? "Launch" : "Games"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [launcher.artStart, launcher.artEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: launcher.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9)).padding(16)
            }
            .frame(height: 96)
            .overlay(alignment: .topTrailing) {
                // Platform badge: native macOS vs Windows (runs via Wine).
                Label(launcher.isMac ? "macOS" : "Windows", systemImage: launcher.isMac ? "apple.logo" : "pc")
                    .font(.system(size: 9, weight: .heavy)).labelStyle(.titleAndIcon)
                    .padding(.vertical, 3).padding(.horizontal, 7)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .foregroundStyle(.white.opacity(0.95)).padding(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(launcher.name).font(.system(size: 16, weight: .semibold))
                Text(launcher.tagline).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(height: 32, alignment: .top)

                HStack {
                    if loading {
                        ProgressView().controlSize(.small)
                        Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Label(statusText, systemImage: statusIcon)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(statusTint)
                        Spacer()
                        Menu {
                            Button { onOpen() } label: { Label("Details & compatibility", systemImage: "info.circle") }
                            if let onInstallLocation {
                                Button(action: onInstallLocation) { Label("Install location…", systemImage: "folder") }
                            }
                            if let onRemove {
                                Divider()
                                Button(role: .destructive, action: onRemove) { Label("Remove store", systemImage: "trash") }
                            }
                        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            .help("Details, compatibility, and remove")
                        ActionPill(title: actionTitle, filled: launcher.status != .comingSoon) { primaryAction() }
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(Color.secondary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    private func primaryAction() {
        // User-added custom store → launch its client (native .app or Windows bottle).
        if launcher.id.hasPrefix("custom-store:") {
            if let e = CustomStoresStore.shared.entry(forLauncherID: launcher.id) {
                ActivityStore.shared.show("Starting \(launcher.name)…"); LaunchService.launchCustomStore(e)
            }
            return
        }
        switch launcher.id {
        case "steam":
            if isConnected { ActivityStore.shared.show("Starting Steam…"); LaunchService.launchSteam() }
            else { onOpen() }               // Steam sign-in setup sheet
        case "epic":
            onOpen()                          // Epic sign-in / games sheet
        case "gog":
            onOpen()                          // GOG sign-in sheet
        case "ubisoft":
            ActivityStore.shared.show("Starting Ubisoft Connect…"); LaunchService.launchUbisoft()
        case "origin":
            ActivityStore.shared.show("Starting Origin…"); LaunchService.launchOrigin()
        default:
            // Generic store template (Battle.net, developer-added, imported).
            if let t = StoreTemplates.shared.template(launcher.id), t.kind == .generic {
                ActivityStore.shared.show("Starting \(launcher.name)…"); LaunchService.launchTemplate(t)
            } else {
                ActivityStore.shared.show("\(launcher.name) isn't wired up yet, see setup"); onOpen()
            }
        }
    }
}

/// Setup help / detail for a store, including its Compatibility options.
/// Every launcher exposes a compat panel: the engine it runs on (a picker where
/// alternatives exist) plus optional Wine DLL overrides. Choices
/// persist to overrides.json keyed by the launcher id and are applied on next launch
/// by LaunchService.launcherEnv → the launch scripts (origin.sh honours ORIGIN_ENGINE;
/// all scripts honour WINEDLLOVERRIDES).
struct LauncherHelpSheet: View {
    let launcher: Launcher
    @Environment(\.dismiss) private var dismiss
    @State private var engine: String = ""
    @State private var dllOverrides: String = ""
    @State private var confirmRemove = false

    private var isCustomStore: Bool { launcher.id.hasPrefix("custom-store:") }

    /// Selectable engines per launcher: (value, label). One entry = fixed/informational.
    private var engineOptions: [(String, String)] {
        switch launcher.id {
        case "origin":  return [("wine-stable", "Wine 11 (recommended)"), ("wine-cef", "CrossOver CEF (fallback)")]
        case "ubisoft": return [("wine-cef", "CrossOver CEF + DXMT bridge")]
        case "steam":   return [("wine-stable", "Wine 11 + DXMT")]
        case "epic":    return [("legendary", "Legendary CLI (per-game compat)")]
        case "gog":     return [("gogdl", "gogdl / D3DMetal (per-game compat)")]
        default:        return [("wine-stable", "Wine 11")]
        }
    }
    /// Client launchers run a Wine GUI, so DLL overrides make sense; the CLI ones
    /// (Epic/GOG) apply compat per game instead.
    private var hasDLLOverrides: Bool { ["origin", "ubisoft", "steam"].contains(launcher.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: launcher.symbol).font(.system(size: 22)).foregroundStyle(DS.accent)
                Text(launcher.name).font(.system(size: 20, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            Label(launcher.status.rawValue, systemImage: "circle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(launcher.status.tint)
            helpRow("How Uncork runs it", launcher.runsVia)

            Divider().opacity(0.4)
            Text("COMPATIBILITY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if engineOptions.count > 1 {
                HStack {
                    Text("Engine").font(.system(size: 13)).frame(width: 70, alignment: .leading)
                    Picker("", selection: $engine) {
                        ForEach(engineOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                    .onChange(of: engine) { UserOverrides.shared.setProfile(launcher.id, engine) }
                }
            } else {
                helpRow("Engine", engineOptions.first?.1 ?? "Wine 11")
            }
            if hasDLLOverrides {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DLL overrides").font(.system(size: 13))
                    TextField("e.g. d3d11=b;dxgi=b", text: $dllOverrides)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                        .onSubmit { UserOverrides.shared.setDLLOverridesString(launcher.id, dllOverrides) }
                    Text("Wine DLL override string (n=native, b=builtin). Applied on next launch.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.4)
            Button {
                TemplateService.exportWithPanel(TemplateService.currentTemplate(forLauncherID: launcher.id))
            } label: {
                Label("Save as Template…", systemImage: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(DS.accent)
            Text("Export this store's engine + Windows version + tweaks as a shareable recipe others can Run.")
                .font(.system(size: 10)).foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) { confirmRemove = true } label: {
                Label(isCustomStore ? "Remove store" : "Remove store (delete its bottle)", systemImage: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.red)
        }
        .padding(22).frame(width: 460, height: 520)
        .confirmationDialog("Remove \(launcher.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove \(launcher.name)", role: .destructive) { removeStore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isCustomStore
                 ? "Removes this store from Uncork. Its bottle stays on disk unless you delete it separately."
                 : "Removes \(launcher.name) and deletes its Wine bottle (games installed inside it are removed). You can set it up again anytime.")
        }
        .onAppear {
            let saved = UserOverrides.shared.profile(launcher.id)
            engine = (saved.isEmpty || saved == "auto") ? (engineOptions.first?.0 ?? "") : saved
            dllOverrides = UserOverrides.shared.dllOverridesString(launcher.id)
        }
    }

    private func removeStore() {
        if isCustomStore {
            if let e = CustomStoresStore.shared.entry(forLauncherID: launcher.id) {
                CustomStoresStore.shared.remove(id: e.id)
            }
        } else {
            // Built-in template store → delete its bottle + forget the sign-in.
            StoreRegistry.shared.uninstall(launcher.id)
            // If it's a user/dev-imported template, also drop its definition so it
            // leaves the store list.
            if StoreTemplates.shared.template(launcher.id)?.kind == .generic {
                TemplateService.removeUserTemplate(id: launcher.id)
            }
        }
        dismiss()
    }

    private func helpRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Epic: in-app sign-in, then browse & install owned games.
struct EpicSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var loggedIn = EpicAuth.isLoggedIn()
    @State private var account = EpicAuth.accountName()
    @State private var code = ""
    @State private var authorizing = false

    @State private var games: [EpicAuth.OwnedGame] = []
    @State private var installed: Set<String> = []
    @State private var installing: Set<String> = []
    @State private var loadingGames = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "e.square.fill").font(.system(size: 22)).foregroundStyle(DS.accent)
                Text("Epic Games").font(.system(size: 20, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }

            if loggedIn {
                Label("Signed in\(account.map { " as \($0)" } ?? "")", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                Text("Install a game: it downloads in the background and appears in your Library.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)

                if loadingGames {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading your Epic library…").font(.system(size: 12)) }
                        .frame(maxWidth: .infinity, alignment: .center).padding(.top, 30)
                } else if games.isEmpty {
                    Text("No owned games found.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(games) { g in gameRow(g) }
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text("Sign in once, no Epic app needed. Uncork connects directly to your Epic account.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                step(1, "Open the Epic sign-in page and log in.")
                Button { EpicAuth.openLogin(); ActivityStore.shared.show("Opened Epic sign-in in your browser") } label: {
                    Label("Open Epic sign-in", systemImage: "safari").font(.system(size: 13, weight: .semibold))
                }
                step(2, "The page shows a sign-in code: copy it and paste it below:")
                HStack {
                    TextField("Paste sign-in code", text: $code).textFieldStyle(.roundedBorder)
                    Button { authorize() } label: { Text("Connect").font(.system(size: 13, weight: .semibold)) }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || authorizing)
                }
                Spacer()
            }
        }
        .padding(22).frame(width: 500, height: 440)
        .onAppear { if loggedIn { loadGames() } }
    }

    private func gameRow(_ g: EpicAuth.OwnedGame) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(g.title).font(.system(size: 13)).lineLimit(1)
                Spacer()
                if installed.contains(g.app) {
                    Label("In Library", systemImage: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                } else if installing.contains(g.app) {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing…").font(.system(size: 11)) }
                } else {
                    Button {
                        installing.insert(g.app)
                        DownloadManager.shared.startEpic(app: g.app, title: g.title, cover: g.cover.flatMap { URL(string: $0) })
                    } label: { Text("Install").font(.system(size: 11, weight: .bold)).padding(.vertical, 4).padding(.horizontal, 12) }
                        .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent))
                }
            }
            .padding(.vertical, 7)
            Divider().opacity(0.3)
        }
    }

    private func authorize() {
        authorizing = true
        ActivityStore.shared.show("Signing in to Epic…", seconds: 8)
        let entered = code
        DispatchQueue.global().async {
            let ok = EpicAuth.authorize(code: entered)
            DispatchQueue.main.async {
                authorizing = false; loggedIn = ok; account = EpicAuth.accountName()
                ActivityStore.shared.show(ok ? "Signed in to Epic ✓" : "Sign-in failed, check the code")
                if ok { loadGames() }
            }
        }
    }

    private func loadGames() {
        loadingGames = true
        DispatchQueue.global(qos: .userInitiated).async {
            let owned = EpicAuth.ownedGames()
            let inst = EpicAuth.installedAppNames()
            DispatchQueue.main.async { games = owned; installed = inst; loadingGames = false }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(DS.accent))
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Steam sign-in guidance (Steam has no code-flow like Epic, so we guide + open it).
struct SteamSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var installer = StoreInstaller.shared
    @State private var loggedIn = SteamAuth.isLoggedIn()
    @State private var account = SteamAuth.accountName()
    @State private var confirmReprovision = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "cloud.fill").font(.system(size: 22)).foregroundStyle(DS.accent)
                Text("Steam").font(.system(size: 20, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }

            if loggedIn {
                Label("Signed in\(account.map { " as \($0)" } ?? "")", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                Text("Your Steam games are in the Library. Hit Play to launch; Steam runs hidden in the background.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
            } else {
                Text("Sign in to Steam once. After that Uncork signs you in automatically and Steam stays hidden.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                step(1, "Open Steam: a sign-in window appears.")
                Button {
                    LaunchService.launchSteam()
                    ActivityStore.shared.show("Opening Steam sign-in… (give it a moment)")
                } label: { Label("Open Steam to sign in", systemImage: "cloud").font(.system(size: 13, weight: .semibold)) }
                step(2, "Scan the QR code with the Steam mobile app, or use your account name + password.")
                step(3, "When your library loads, click below to confirm.")
                Button("I've signed in") {
                    loggedIn = SteamAuth.isLoggedIn(); account = SteamAuth.accountName()
                    ActivityStore.shared.show(loggedIn ? "Steam connected ✓" : "Not detected yet, finish signing in")
                }
                Text("Didn't work? Make sure Rosetta is installed (see Setup). If the Steam window never appeared, quit any running Steam and try “Open Steam” again.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                steamTroubleshooting
                Spacer()
            }
        }
        .padding(22).frame(width: 480, height: 430)
        .confirmationDialog("Reprovision Steam from scratch?",
                            isPresented: $confirmReprovision, titleVisibility: .visible) {
            Button("Reprovision", role: .destructive) {
                StoreInstaller.shared.applyFix(key: "steam-reprovision",
                                               script: "steam-reprovision.sh",
                                               bottle: "steam",
                                               label: "Reprovisioning Steam from scratch…",
                                               extraEnv: ["UNCORK_REPROVISION_CONFIRM": "1"])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wipes the Steam client and reinstalls it from Valve (your installed games and logins are kept). Use this to fix a broken client or test a fresh install.")
        }
    }

    // The real fixes (stage client from Valve, single-process CEF shim, freeze) now
    // run automatically during setup, so they need no buttons. All that's left on the
    // sign-in sheet is one low-key recovery action: a full clean-slate reinstall for
    // the rare case setup left Steam broken (confirmation-gated).
    @ViewBuilder private var steamTroubleshooting: some View {
        let fix = installer.status("steam-reprovision")
        Divider().padding(.vertical, 2)
        if fix.phase == .installing {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fix.fraction)
                Text(fix.message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Text("Trouble with Steam?").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Reset & reinstall") { confirmReprovision = true }
                    .font(.system(size: 11, weight: .semibold)).buttonStyle(.link)
                if fix.phase == .done {
                    Label("done", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else if fix.phase == .failed {
                    Text(fix.message).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(DS.accent))
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
