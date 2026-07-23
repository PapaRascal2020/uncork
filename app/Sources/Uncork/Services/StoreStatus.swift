import Foundation
import Combine

/// Live sign-in status for the stores, shown in the sidebar footer so the user
/// can see Steam signing in (e.g. during pre-warm) instead of wondering. Polls
/// lightly on a timer while the app is open.
final class StoreStatus: ObservableObject {
    static let shared = StoreStatus()

    enum State: Equatable { case notSetUp, signingIn, signedIn }

    @Published private(set) var steam: State = .notSetUp
    @Published private(set) var epic: State = .notSetUp
    @Published private(set) var gog: State = .notSetUp

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async {
            // Steam: base "signed in" on the persistent sign-in (a prior login leaves
            // userdata/<steamid> + remembered credentials), not the live connection
            // log: otherwise a background prewarm shows "signing in" then drops to
            // hidden when the process stops, flickering Steam in and out of the footer.
            // This matches how Epic/GOG report status (persistent token), so a set-up
            // Steam stays "Signed in" stably. A live connection also counts; the
            // transient "signing in" only shows when running before any sign-in exists.
            let steamInstalled = FileManager.default.fileExists(atPath: Paths.steamDir + "/steam.exe")
            let steamSignedIn = SteamAuth.isLoggedIn()
            let steamConnected = Self.steamConnected()
            let steamRunning = SteamService.isRunning()
            let s: State = !steamInstalled ? .notSetUp
                : (steamSignedIn || steamConnected) ? .signedIn
                : steamRunning ? .signingIn
                : .notSetUp
            // Epic: token present = signed in (CLI has no separate "connecting").
            let e: State = EpicAuth.isLoggedIn() ? .signedIn : .notSetUp
            // GOG: token present = signed in (gogdl, no separate "connecting").
            let g: State = GogAuth.isLoggedIn() ? .signedIn : .notSetUp
            DispatchQueue.main.async {
                if self.steam != s { self.steam = s }
                if self.epic != e { self.epic = e }
                if self.gog != g { self.gog = g }
            }
        }
    }

    /// Currently connected iff the most recent connection event is 'Logged On'.
    private static func steamConnected() -> Bool {
        let log = Paths.steamDir + "/logs/connection_log.txt"
        guard let text = try? String(contentsOfFile: log, encoding: .utf8) else { return false }
        var last = ""
        for line in text.split(whereSeparator: \.isNewline) {
            if line.contains("Logged On") || line.contains("Logged Off") { last = String(line) }
        }
        return last.contains("Logged On")
    }
}
