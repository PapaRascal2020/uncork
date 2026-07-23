import SwiftUI

/// The end-user guide, shown inside the app: a self-contained, Laravel-docs-styled
/// HTML page (docs/user-guide.html in the payload) rendered in a WKWebView, exactly
/// like the Developer Guide but written for players rather than contributors.
/// Fully offline and theme-aware.
struct UserGuideView: View {
    private var htmlPath: String { Paths.payload + "/docs/user-guide.html" }
    @State private var missing = false

    var body: some View {
        Group {
            if missing {
                ContentUnavailableView("Guide not found", systemImage: "book.closed",
                    description: Text("docs/user-guide.html isn't in the payload."))
            } else {
                DocWebView(path: htmlPath)
            }
        }
        .navigationTitle("User Guide")
        .onAppear { missing = !FileManager.default.fileExists(atPath: htmlPath) }
    }
}
