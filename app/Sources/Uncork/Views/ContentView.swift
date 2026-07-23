import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case stores    = "Stores"
    case library   = "Library"
    case downloads = "Downloads"
    case epicStore = "Epic Store"
    case wine      = "Wine Downloader"
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
        case .epicStore: return "bag.fill"
        case .wine:      return "wineglass.fill"
        case .setup:     return "wrench.and.screwdriver.fill"
        case .userGuide:  return "book.fill"
        case .developers: return "chevron.left.forwardslash.chevron.right"
        case .about:     return "info.circle.fill"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .stores
    @AppStorage("uncork.hasSeenWelcome") private var seenWelcome = false
    @State private var showWelcome = false
    @ObservedObject private var registry = StoreRegistry.shared
    @ObservedObject private var storeStatus = StoreStatus.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section { row(.stores); row(.library); row(.downloads) }
                // The Epic store browser only makes sense once Epic is set up.
                if registry.isInstalled("epic") {
                    Section("Browse") { row(.epicStore) }
                }
                Section { row(.wine); row(.userGuide); row(.developers); row(.setup); row(.about) }
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
                switch selection ?? .stores {
                case .stores:    StoresView()
                case .library:   LibraryView()
                case .downloads: DownloadsView()
                case .epicStore: EpicStoreView()
                case .wine:      WineManagerView()
                case .setup:     SetupView()
                case .userGuide:  UserGuideView()
                case .developers: DeveloperGuideView()
                case .about:     AboutView()
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
        Label(item.rawValue, systemImage: item.symbol).tag(item)
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
