import Foundation

/// Pre-warms Steam so the first game launch is fast. Steam-on-Linux keeps the
/// client signed in and running; we do the same: start Steam hidden + logged in
/// when Uncork opens, so hitting Play just does `-applaunch` (no cold boot +
/// sign-in wait, which is the slow part of a first launch).
enum SteamService {
    private static var warmed = false

    /// Start Steam hidden ahead of time, but only if it's installed, the user
    /// has signed in before (so we never surprise them with a login window), and
    /// it isn't already running. Runs once per app session, fire-and-forget.
    static func prewarmIfPossible() {
        guard !warmed else { return }
        warmed = true
        DispatchQueue.global(qos: .utility).async {
            let steamExe = Paths.steamDir + "/steam.exe"
            guard FileManager.default.fileExists(atPath: steamExe),
                  SteamAuth.isLoggedIn(),          // only if they've signed in before
                  !isRunning() else { return }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["\(Paths.scripts)/steam.sh", "-silent", "-no-browser"]
            p.environment = Paths.scriptEnvironment(["BOTTLE_NAME": "steam"])
            // Detach output so Steam's chatty logging can't fill a pipe and stall it.
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()   // stays running in the background; we don't wait on it
        }
    }

    static func isRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "[Ss]team.steam\\.exe"]   // match / or \ (Steam re-execs with a Windows path)
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }
}
