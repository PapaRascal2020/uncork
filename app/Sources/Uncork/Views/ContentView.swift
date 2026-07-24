import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case stores    = "Stores"
    case library   = "Library"
    case downloads = "Downloads"
    case wine      = "Wine Downloader"
    case fixes     = "Compatibility"
    case setup     = "Setup"
    case userGuide  = "User Guide"
    case developers = "Developer Guide"
    case about     = "About"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .stores:    return "square.grid.2x2.fill"
        case .library:   return "square.stack.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .wine:      return "wineglass.fill"
        case .fixes:     return "checklist"
        case .setup:     return "wrench.and.screwdriver.fill"
        case .userGuide:  return "book.fill"
        case .developers: return "chevron.left.forwardslash.chevron.right"
        case .about:     return "info.circle.fill"
        }
    }
}

/// Sidebar selection: a fixed section item, or a store's "Browse" web page.
enum Nav: Hashable {
    case item(SidebarItem)
    case browse(String)   // store id: a template id (steam/epic/gog/…) or "custom-store:<id>"
}

/// A store with a web storefront to browse in-app (Steam/Epic/GOG or a custom store).
struct BrowseEntry: Identifiable, Hashable {
    let id: String        // matches Nav.browse(id)
    let name: String
    let symbol: String
    let url: URL
}

struct ContentView: View {
    @State private var selection: Nav? = .item(.stores)
    @AppStorage("uncork.hasSeenWelcome") private var seenWelcome = false
    @State private var showWelcome = false
    @ObservedObject private var registry = StoreRegistry.shared
    @ObservedObject private var storeStatus = StoreStatus.shared
    @ObservedObject private var customStores = CustomStoresStore.shared

    /// Installed stores that expose a web storefront (a built-in template with a
    /// store_url, or a custom store the user gave a store page). These become the
    /// sidebar's "Browse" rows.
    private var browseEntries: [BrowseEntry] {
        var out: [BrowseEntry] = []
        for l in registry.installed {
            if let t = StoreTemplates.shared.template(l.id), let u = Self.normalizedURL(t.storeURL) {
                out.append(BrowseEntry(id: l.id, name: t.name, symbol: t.symbol, url: u))
            }
        }
        for e in customStores.entries {
            if let s = e.storeURL, let u = Self.normalizedURL(s) {
                out.append(BrowseEntry(id: "custom-store:\(e.id)", name: e.name, symbol: e.symbol, url: u))
            }
        }
        return out
    }

    /// Accept a bare host ("gog.com") as well as a full URL.
    static func normalizedURL(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return URL(string: t.contains("://") ? t : "https://\(t)")
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section { row(.stores); row(.library); row(.downloads) }
                // A store's web storefront, shown once that store is set up.
                if !browseEntries.isEmpty {
                    Section("Browse") { ForEach(browseEntries) { browseRow($0) } }
                }
                Section { row(.wine); row(.fixes); row(.userGuide); row(.developers); row(.setup); row(.about) }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "wineglass.fill").foregroundStyle(DS.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Uncork").font(.headline)
                        Text("play anything on your Mac")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            }
            .safeAreaInset(edge: .bottom) { signInFooter }
        } detail: {
            Group {
                switch selection ?? .item(.stores) {
                case .item(let it):
                    switch it {
                    case .stores:    StoresView()
                    case .library:   LibraryView()
                    case .downloads: DownloadsView()
                    case .wine:      WineManagerView()
                    case .fixes:     CompatFixesView()
                    case .setup:     SetupView()
                    case .userGuide:  UserGuideView()
                    case .developers: DeveloperGuideView()
                    case .about:     AboutView()
                    }
                case .browse(let id):
                    // Fresh session per store (.id) so switching stores never reuses
                    // the previous store's page. Falls back if the store was removed.
                    if let b = browseEntries.first(where: { $0.id == id }) {
                        StoreBrowserView(name: b.name, url: b.url).id(b.id)
                    } else {
                        StoresView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
        .overlay { ToastView() }
        .onAppear {
            if !seenWelcome { showWelcome = true }
            SteamService.prewarmIfPossible()   // sign Steam in ahead of time → fast Play
            storeStatus.start()                // live sign-in status in the footer
        }
        .sheet(isPresented: $showWelcome) { SetupWizard(onDone: { seenWelcome = true }) }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.rawValue, systemImage: item.symbol).tag(Nav.item(item))
    }

    private func browseRow(_ b: BrowseEntry) -> some View {
        Label(b.name, systemImage: b.symbol).tag(Nav.browse(b.id))
    }

    /// Bottom-left store sign-in status: shown only for stores that are
    /// connecting or connected, so the user can see Steam signing in (pre-warm).
    @ViewBuilder private var signInFooter: some View {
        if storeStatus.steam != .notSetUp || storeStatus.epic != .notSetUp || storeStatus.gog != .notSetUp {
            VStack(alignment: .leading, spacing: 6) {
                Divider().opacity(0.4)
                if storeStatus.steam != .notSetUp { statusRow("Steam", "cloud.fill", storeStatus.steam) }
                if storeStatus.epic != .notSetUp { statusRow("Epic", "e.square.fill", storeStatus.epic) }
                if storeStatus.gog != .notSetUp { statusRow("GOG", "g.square.fill", storeStatus.gog) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    @ViewBuilder private func statusRow(_ name: String, _ symbol: String, _ s: StoreStatus.State) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
            Text(name).font(.system(size: 11, weight: .medium))
            Spacer()
            switch s {
            case .signingIn:
                ProgressView().controlSize(.mini)
                Text("Signing in…").font(.system(size: 10)).foregroundStyle(.secondary)
            case .signedIn:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(.green)
                Text("Signed in").font(.system(size: 10)).foregroundStyle(.secondary)
            case .notSetUp:
                EmptyView()
            }
        }
    }
}
