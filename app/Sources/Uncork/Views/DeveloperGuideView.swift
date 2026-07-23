import SwiftUI
import WebKit

/// Renders the open-source developer guide inside the app. The guide ships as a
/// self-contained, Laravel-docs-styled HTML page (docs/developer-guide.html in
/// the payload) shown in a WKWebView, so contributors read the real, styled docs
/// without leaving Uncork or opening a browser. The page is fully offline and
/// theme-aware (it follows the system light/dark and has its own toggle).
struct DeveloperGuideView: View {
    private var htmlPath: String { Paths.payload + "/docs/developer-guide.html" }
    @State private var missing = false

    var body: some View {
        Group {
            if missing {
                ContentUnavailableView("Guide not found", systemImage: "book.closed",
                    description: Text("docs/developer-guide.html isn't in the payload."))
            } else {
                DocWebView(path: htmlPath)
            }
        }
        .navigationTitle("Developer Guide")
        .onAppear { missing = !FileManager.default.fileExists(atPath: htmlPath) }
    }
}

/// Thin WKWebView wrapper that loads a local HTML file once (no reload churn on
/// SwiftUI updates), granting read access to the docs dir for any local assets.
/// Shared by the Developer Guide and the User Guide.
struct DocWebView: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.setValue(false, forKey: "drawsBackground")   // let the page's own background show
        let url = URL(fileURLWithPath: path)
        wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
