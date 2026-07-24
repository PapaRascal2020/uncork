import SwiftUI
import WebKit
import AppKit

/// A WKWebView plus the navigation state a store page needs (back/forward/reload).
/// The website data store is persistent, so a one-time sign-in on a store survives
/// app relaunches.
final class WebViewModel: ObservableObject {
    let web: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL: URL?
    private var observers: [NSKeyValueObservation] = []

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        web = WKWebView(frame: .zero, configuration: config)
        observers = [
            web.observe(\.canGoBack, options: [.initial, .new]) { [weak self] w, _ in self?.canGoBack = w.canGoBack },
            web.observe(\.canGoForward, options: [.initial, .new]) { [weak self] w, _ in self?.canGoForward = w.canGoForward },
            web.observe(\.isLoading, options: [.initial, .new]) { [weak self] w, _ in self?.isLoading = w.isLoading },
            web.observe(\.url, options: [.initial, .new]) { [weak self] w, _ in self?.currentURL = w.url },
        ]
    }

    /// Load once (the view can re-appear without resetting where the user browsed to).
    func loadIfNeeded(_ url: URL) { if web.url == nil { web.load(URLRequest(url: url)) } }
}

/// Bridges the model's WKWebView into SwiftUI. The view is owned by the model so
/// toolbar controls can drive it directly.
struct WebViewContainer: NSViewRepresentable {
    let model: WebViewModel
    func makeNSView(context: Context) -> WKWebView { model.web }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Browse a store's web storefront inside Uncork: buy or claim here, then install
/// from the Library. Used for Steam, Epic and GOG, and for any custom store that
/// has a store page set. Give the view a stable `.id(storeID)` so switching stores
/// starts a fresh session rather than reusing the previous store's page.
struct StoreBrowserView: View {
    let name: String
    let url: URL
    @StateObject private var model = WebViewModel()

    var body: some View {
        WebViewContainer(model: model)
            .navigationTitle("\(name) Store")
            .toolbar {
                ToolbarItemGroup {
                    Button { model.web.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.canGoBack).help("Back")
                    Button { model.web.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.canGoForward).help("Forward")
                    Button {
                        if model.isLoading { model.web.stopLoading() } else { model.web.reload() }
                    } label: {
                        Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                    }.help(model.isLoading ? "Stop" : "Reload")
                    Button { NSWorkspace.shared.open(model.currentURL ?? url) } label: {
                        Image(systemName: "safari")
                    }.help("Open this page in your browser")
                    Button {
                        ActivityStore.shared.show("Bought or claimed something? Open Library and refresh to install it.")
                    } label: { Image(systemName: "questionmark.circle") }
                    .help("After buying or claiming, go to Library and refresh to install it")
                }
            }
            .onAppear { model.loadIfNeeded(url) }
    }
}
