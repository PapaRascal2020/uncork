import SwiftUI
import WebKit

/// Embedded web view (used for the Epic store).
struct WebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Persistent (disk-backed) cookie/session store, so a one-time Epic
        // sign-in in this tab survives app relaunches.
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.load(URLRequest(url: url))
        return web
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Browse the Epic store inside Uncork. Claim/buy here, then install from the
/// Library (which reads your owned games via legendary).
struct EpicStoreView: View {
    private let store = URL(string: "https://store.epicgames.com/")!

    var body: some View {
        WebView(url: store)
            .navigationTitle("Epic Store")
            .toolbar {
                Button {
                    ActivityStore.shared.show("Claimed something? Open Library and refresh to install.")
                } label: { Image(systemName: "questionmark.circle") }
                .help("After claiming a game, go to Library → refresh to install it")
            }
    }
}
