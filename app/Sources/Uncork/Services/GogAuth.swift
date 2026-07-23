import Foundation
import AppKit

/// In-app GOG sign-in via gogdl's OAuth code flow (mirrors EpicAuth): open GOG's
/// login in the browser, the user copies the `code=` value from the redirect
/// URL, pastes it back into Uncork, and we hand it to gogdl.
enum GogAuth {
    /// GOG login using GOG Galaxy's client id + the client redirect. After signing
    /// in, the browser lands on embed.gog.com/on_login_success?...&code=XXXX: the
    /// code is in the address bar.
    static let loginURL = URL(string:
        "https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=client2")!

    static func isLoggedIn() -> Bool {
        Shell.run(script: "gog.sh", ["status"]).contains("GOG account: signed in")
    }

    static func openLogin() { NSWorkspace.shared.open(loginURL) }

    /// Exchange the pasted authorization code for a session. Returns success.
    static func authorize(code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        _ = Shell.run(script: "gog.sh", ["auth", "--code", trimmed])
        return isLoggedIn()
    }
}
