import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Library = games from any store (Steam + Epic) plus user-added apps, each
/// launchable directly from Uncork.
struct LibraryView: View {
    @ObservedObject private var lib = LibraryStore.shared
    @ObservedObject private var dl = DownloadManager.shared
    @ObservedObject private var org = LibraryOrganizer.shared
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 18)]

    // Filters
    @State private var query = ""
    @State private var store: StoreFilter = .all
    @State private var status: StatusFilter = .all
    @State private var compat: CompatFilter = .all
    @State private var platform: PlatformFilter = .all
    // Organization filters
    @State private var favoritesOnly = false
    @State private var showHidden = false
    @State private var collection: String? = nil   // nil = all collections

    // New-collection prompt (raised from a game's context menu)
    @State private var showNewCollection = false
    @State private var newCollectionName = ""
    @State private var newCollectionTarget: InstalledGame?

    // Add-a-game (custom .exe / native .app) flow
    @State private var addExe: String?
    @State private var addTitle = ""
    @State private var addIsolated = true
    @State private var addPlatform = "windows"   // "windows" (.exe via Wine) | "mac" (native .app)

    private var filtered: [InstalledGame] {
        lib.games.filter { g in
            (query.isEmpty || g.title.localizedCaseInsensitiveContains(query))
            && store.matches(g) && status.matches(g) && compat.matches(g) && platform.matches(g)
            // Hidden games are set aside unless "Show hidden" is on.
            && (showHidden || !org.isHidden(g.id))
            && (!favoritesOnly || org.isFavorite(g.id))
            && (collection == nil || org.inCollection(g.id, collection!))
        }
    }
    private var filtersActive: Bool {
        store != .all || status != .all || compat != .all || platform != .all
            || favoritesOnly || showHidden || collection != nil
    }
    /// The Mac|Windows tab is only useful once you own a title with a native Mac
    /// build (GOG flags these). Hidden otherwise so Windows-only libraries stay clean.
    private var hasMacGames: Bool { lib.games.contains { $0.hasMac } }
    /// Shown beside the "Library" title. Total games, or "X of Y" while filtering.
    private var countLabel: String {
        let total = lib.games.count
        guard total > 0 else { return "" }
        let showing = filtered.count
        let word = total == 1 ? "game" : "games"
        return (filtersActive || !query.isEmpty) && showing != total
            ? "\(showing) of \(total) \(word)"
            : "\(total) \(word)"
    }
    private func clearFilters() {
        store = .all; status = .all; compat = .all; platform = .all; query = ""
        favoritesOnly = false; showHidden = false; collection = nil
    }

    /// The library filter menu (store / show / compatibility / organization).
    @ViewBuilder private var filterMenu: some View {
        Picker("Store", selection: $store) {
            ForEach(StoreFilter.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.inline)
        Picker("Show", selection: $status) {
            ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.inline)
        Picker("Compatibility", selection: $compat) {
            ForEach(CompatFilter.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.inline)
        Divider()
        Toggle("Favorites only", isOn: $favoritesOnly)
        Toggle("Show hidden", isOn: $showHidden)
        if !org.collectionNames.isEmpty {
            Picker("Collection", selection: $collection) {
                Text("All collections").tag(String?.none)
                ForEach(org.collectionNames, id: \.self) { Text($0).tag(Optional($0)) }
            }
        }
        if filtersActive { Divider(); Button("Clear Filters", action: clearFilters) }
    }

    /// Right-click actions on a Library tile: favorite, hide, and collections.
    @ViewBuilder private func gameContextMenu(_ g: InstalledGame) -> some View {
        Button {
            org.toggleFavorite(g.id)
        } label: {
            Label(org.isFavorite(g.id) ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: org.isFavorite(g.id) ? "star.slash" : "star")
        }
        Button {
            org.setHidden(g.id, !org.isHidden(g.id))
        } label: {
            Label(org.isHidden(g.id) ? "Unhide" : "Hide game",
                  systemImage: org.isHidden(g.id) ? "eye" : "eye.slash")
        }
        Menu {
            ForEach(org.collectionNames, id: \.self) { c in
                Button { org.toggleCollection(g.id, c) } label: {
                    Label(c, systemImage: org.inCollection(g.id, c) ? "checkmark" : "circle")
                }
            }
            if !org.collectionNames.isEmpty { Divider() }
            Button { newCollectionTarget = g; newCollectionName = ""; showNewCollection = true } label: {
                Label("New Collection…", systemImage: "plus")
            }
        } label: { Label("Collections", systemImage: "folder") }
    }

    /// The scrolling body: platform tab, empty states, and the game grid. Kept as
    /// its own view so the `body` below stays small enough to type-check quickly.
    @ViewBuilder private var scrollContent: some View {
        // Mac | Windows | All tab: always shown so you can filter by platform.
        if !lib.games.isEmpty {
            Picker("", selection: $platform) {
                ForEach(PlatformFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.gutter)
        }
        if lib.games.isEmpty {
            ContentUnavailableView(
                "Nothing here yet",
                systemImage: "tray",
                description: Text("Connect a store on the Stores tab. Owned games show here: install then play, all in one place."))
                .padding(.top, 90)
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("No games match", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try a different search or clear the filters.")
            } actions: {
                Button("Clear Filters", action: clearFilters)
            }
            .padding(.top, 90)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(filtered) { g in
                    NavigationLink(value: g) { InstalledGameCard(game: g) }
                        .buttonStyle(.plain)
                        .contextMenu { gameContextMenu(g) }
                }
            }
            .padding(DS.Space.gutter)
        }
    }

    var body: some View {
      NavigationStack {
        ScrollView { scrollContent }
        .overlay(alignment: .top) {
            if lib.loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Refreshing your library…").font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lib.loading)
        .navigationTitle("Library")
        .navigationSubtitle(countLabel)
        .searchable(text: $query, placement: .automatic, prompt: "Search games")
        .onAppear { lib.loadIfNeeded() }   // scans once per session; instant thereafter
        .onChange(of: dl.all.filter { $0.done }.count) { _ in lib.refresh() }  // an install finished
        .toolbar {
            ToolbarItem {
                Menu {
                    Button { pickExe() } label: { Label("Add Windows Game…", systemImage: "window.casement") }
                    Button { pickApp() } label: { Label("Add Mac Game…", systemImage: "apple.logo") }
                } label: { Image(systemName: "plus") }
                .help("Add a game: a Windows .exe (via Wine) or a native macOS .app")
                .accessibilityLabel("Add a game")
            }
            ToolbarItem {
                Menu { filterMenu } label: {
                    Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill"
                                                     : "line.3.horizontal.decrease.circle")
                }
                .help("Filter the library").accessibilityLabel("Filter the library")
            }
            ToolbarItem {
                Button { lib.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(lib.loading).help("Refresh library").accessibilityLabel("Refresh library")
            }
        }
        .navigationDestination(for: InstalledGame.self) { GameDetailView(game: $0) }
        .alert("New Collection", isPresented: $showNewCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") {
                if let g = newCollectionTarget { org.addToCollection(g.id, newCollectionName) }
                newCollectionTarget = nil; newCollectionName = ""
            }
            Button("Cancel", role: .cancel) { newCollectionTarget = nil; newCollectionName = "" }
        } message: {
            Text("Group games together. This adds the selected game to a new collection.")
        }
        .sheet(isPresented: Binding(get: { addExe != nil }, set: { if !$0 { addExe = nil } })) {
            AddGameSheet(exePath: addExe ?? "", platform: addPlatform, title: $addTitle, isolated: $addIsolated,
                onAdd: {
                    CustomGamesStore.shared.add(exePath: addExe ?? "", title: addTitle,
                                                isolated: addIsolated, platform: addPlatform)
                    addExe = nil
                    lib.refresh()
                },
                onCancel: { addExe = nil })
        }
      }
    }

    private func pickExe() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a Windows .exe to run through Uncork"
        if panel.runModal() == .OK, let url = panel.url {
            addTitle = url.deletingPathExtension().lastPathComponent
            addIsolated = true
            addPlatform = "windows"
            addExe = url.path
        }
    }

    /// Pick a NATIVE macOS game: a .app bundle (or a native binary). It runs
    /// directly, with no Wine/engine.
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application, .unixExecutable]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false   // pick the .app itself
        panel.message = "Choose a native macOS game (.app) to add"
        if panel.runModal() == .OK, let url = panel.url {
            addTitle = url.deletingPathExtension().lastPathComponent
            addIsolated = false
            addPlatform = "mac"
            addExe = url.path
        }
    }
}

/// Sheet to name a user-added .exe and choose whether it gets its own bottle.
struct AddGameSheet: View {
    let exePath: String
    var platform: String = "windows"   // "mac" = native .app (no bottle); else .exe via Wine
    @Binding var title: String
    @Binding var isolated: Bool
    var onAdd: () -> Void
    var onCancel: () -> Void

    private var isMac: Bool { platform == "mac" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: isMac ? "apple.logo" : "window.casement").foregroundStyle(DS.accent)
                Text(isMac ? "Add Mac Game" : "Add Windows Game").font(.system(size: 20, weight: .bold))
            }
            HStack(spacing: 6) {
                Image(systemName: "app.dashed").foregroundStyle(.secondary)
                Text((exePath as NSString).lastPathComponent)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Name").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Game name", text: $title).textFieldStyle(.roundedBorder)
                }
                if isMac {
                    Label("Runs natively (no Wine, no bottle).", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12)).foregroundStyle(.green)
                } else {
                    Toggle(isOn: $isolated) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Isolated prefix").font(.system(size: 13, weight: .medium))
                            Text("Give it its own Wine bottle: keeps this game's fixes and runtimes separate from others (recommended).")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.toggleStyle(.switch).tint(DS.accent)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.secondary.opacity(0.10)))

            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                let disabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                Button(action: onAdd) {
                    Text("Add to Library").font(.system(size: 13, weight: .bold))
                        .padding(.vertical, 6).padding(.horizontal, 16)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Capsule().fill(DS.accent.opacity(disabled ? 0.4 : 1)))
                .keyboardShortcut(.defaultAction).disabled(disabled)
            }
        }
        .padding(22).frame(width: 440)
    }
}

// MARK: - Library filters

enum StoreFilter: String, CaseIterable, Identifiable {
    case all = "All Stores", steam = "Steam", epic = "Epic", gog = "GOG", custom = "Added apps"
    var id: String { rawValue }
    func matches(_ g: InstalledGame) -> Bool {
        switch self {
        case .all:    return true
        case .steam:  return g.source == .steam
        case .epic:   return g.source == .epic
        case .gog:    return g.source == .gog
        case .custom: return g.source == .custom
        }
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "Installed & not", installed = "Installed only", available = "Not installed"
    var id: String { rawValue }
    func matches(_ g: InstalledGame) -> Bool {
        switch self {
        case .all:       return true
        case .installed: return g.installed
        case .available: return !g.installed
        }
    }
}

enum PlatformFilter: String, CaseIterable, Identifiable {
    case all = "All", windows = "Windows", mac = "Mac"
    var id: String { rawValue }
    func matches(_ g: InstalledGame) -> Bool {
        switch self {
        case .all:     return true
        case .windows: return g.platforms.contains(.windows)
        case .mac:     return g.platforms.contains(.mac)
        }
    }
}

enum CompatFilter: String, CaseIterable, Identifiable {
    case all = "Any status", works = "Should work", notYet = "Needs work", untested = "Untested"
    var id: String { rawValue }
    func matches(_ g: InstalledGame) -> Bool {
        switch self {
        case .all:      return true
        case .works:    return GameCompat.of(g) == .works
        case .notYet:   return GameCompat.of(g) == .notYet
        case .untested: return GameCompat.of(g) == .untested
        }
    }
}

/// A clean, clickable Library tile: cover art + title + compat. Tapping it opens
/// the game's detail page (where Play + all config live now). Shows live install
/// progress, and dims games that aren't downloaded yet.
struct InstalledGameCard: View {
    let game: InstalledGame
    @ObservedObject private var run = RunStore.shared
    @ObservedObject private var dl = DownloadManager.shared
    @ObservedObject private var art = CustomArtStore.shared
    @ObservedObject private var org = LibraryOrganizer.shared
    @State private var hovering = false

    private var installing: DownloadManager.Item? {
        guard let it = dl.items[game.launchID], !it.done, !it.failed else { return nil }
        return it
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover art as a clean 16:9 box that scales with the tile width. The
            // source badge + status chips are drawn AFTER the clip so the rounded
            // corner can never cut them.
            LinearGradient(colors: [game.art.0, game.art.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    AsyncImage(url: game.artURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.18))
                    }
                }
                .opacity(game.installed || installing != nil ? 1 : 0.55)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Text(game.source.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .padding(.vertical, 3).padding(.horizontal, 7)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) { statusChip }
                .overlay(alignment: .bottomTrailing) { platformBadge }
                // running indicator so you can see what's playing from the grid
                .overlay(alignment: .topLeading) {
                    if run.state(game.id) == .running {
                        Label("Running", systemImage: "play.circle.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.vertical, 3).padding(.horizontal, 7)
                            .background(Capsule().fill(.green.opacity(0.85)))
                            .foregroundStyle(.white).padding(10)
                    }
                }

            HStack(spacing: 5) {
                if org.isFavorite(game.id) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                        .help("Favorite")
                }
                Text(game.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if org.isHidden(game.id) {
                    Image(systemName: "eye.slash.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                        .help("Hidden")
                }
            }
            CompatIndicator(game: game)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())   // whole tile is the tap target
        .opacity(org.isHidden(game.id) ? 0.6 : 1)   // hidden games read as set-aside when shown
        // Subtle Steam-style lift on hover.
        .scaleEffect(hovering ? 1.035 : 1)
        .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: hovering ? 12 : 0, y: hovering ? 6 : 0)
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onHover { hovering = $0 }
    }

    /// Bottom-right platform glyph so every tile shows how it runs at a glance:
    /// Apple logo = native macOS build; "pc" = Windows (runs via Wine).
    @ViewBuilder private var platformBadge: some View {
        Image(systemName: game.hasMac ? "apple.logo" : "pc")
            .font(.system(size: 10, weight: .bold))
            .padding(5)
            .background(Circle().fill(.black.opacity(0.55)))
            .foregroundStyle(.white.opacity(0.95))
            .padding(10)
            .help(game.hasMac ? "Native macOS build" : "Windows game (runs via Wine)")
    }

    /// Bottom-left chip on the art. Installing: live progress. Not installed:
    /// dimmed art (above) + a clear download badge. Installed: a small green check
    /// so a downloaded game reads at a glance without a heavy label.
    @ViewBuilder private var statusChip: some View {
        if let it = installing {
            HStack(spacing: 5) {
                ProgressView(value: it.progress).frame(width: 46).tint(.white)
                Text("\(Int(it.progress * 100))%").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Capsule().fill(.black.opacity(0.6))).padding(10)
        } else if !game.installed {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle").font(.system(size: 9, weight: .heavy))
                Text("NOT INSTALLED").font(.system(size: 9, weight: .heavy)).tracking(0.5)
            }
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(Capsule().fill(.black.opacity(0.6)))
            .foregroundStyle(.white.opacity(0.9)).padding(10)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .background(Circle().fill(.black.opacity(0.45)).padding(1))
                .padding(10)
                .help("Installed")
        }
    }
}

/// Install button for owned-but-not-downloaded games; shows live progress.
struct InstallButton: View {
    let game: InstalledGame
    @ObservedObject private var dl = DownloadManager.shared

    var body: some View {
        if let it = dl.items[game.launchID], !it.done, !it.failed {
            HStack(spacing: 6) {
                ProgressView(value: it.progress).frame(width: 58).tint(DS.accent)
                Text("\(Int(it.progress * 100))%").font(.system(size: 11, weight: .medium))
            }
        } else {
            Button { DownloadManager.shared.startInstall(game) } label: {
                Label("Install", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.vertical, 6).padding(.horizontal, 14)
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            .background(Capsule().fill(Color.blue))
        }
    }
}

/// State-aware launch button: Play → Launching… → Launched, back to Play on exit.
struct PlayButton: View {
    let game: InstalledGame
    @ObservedObject private var run = RunStore.shared

    var body: some View {
        let st = run.state(game.id)
        Button {
            switch st {
            case .idle, .failed:                 // failed → allow retry
                ActivityStore.shared.show("Launching \(game.title)…", seconds: 6)
                run.launch(game)
            case .running: run.stop(game)        // tap while running → quit
            case .launching: break
            }
        } label: {
            Label(title(st), systemImage: icon(st))
                .font(.system(size: 12, weight: .bold))
                .padding(.vertical, 6).padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Capsule().fill(fill(st)))
        .disabled(st == .launching)
        .help(helpText(st))
        .accessibilityLabel(title(st))
        .animation(.easeInOut(duration: 0.2), value: st)
    }

    private func title(_ s: RunState) -> String {
        switch s {
        case .idle: return "Play"
        case .launching: return run.status(game.id) ?? "Launching…"   // live stage
        case .running: return "Quit"; case .failed: return "Try again"
        }
    }
    private func icon(_ s: RunState) -> String {
        switch s {
        case .idle: return "play.fill"; case .launching: return "hourglass"
        case .running: return "stop.fill"; case .failed: return "exclamationmark.arrow.circlepath"
        }
    }
    private func fill(_ s: RunState) -> Color {
        switch s {
        case .idle: return DS.accent; case .launching: return .gray
        case .running: return Color(white: 0.42); case .failed: return .orange
        }
    }
    private func helpText(_ s: RunState) -> String {
        switch s {
        case .running: return "Quit the running game"
        case .failed:  return "The game didn't start, open ⚙ to apply fixes, then try again"
        default:       return ""
        }
    }
}
