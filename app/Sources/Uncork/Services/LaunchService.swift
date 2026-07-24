import Foundation
import AppKit

/// Runs Uncork's shell primitives (launch a game, a store) without blocking the
/// UI. Bridges the SwiftUI buttons to the engine scripts.
enum LaunchService {
    /// Build (but don't start) the launch process for a game, so the caller
    /// (RunStore) can stream its @@STATUS@@ output and manage its lifecycle.
    /// Steam → play.sh (Steam hidden, launched via -applaunch); Epic → legendary
    /// (epic.sh); custom → run-exe.sh in the game's own bottle.
    static func launchProcess(for game: InstalledGame, diagnostic: Bool = false) -> Process? {
        // Every launch writes to a per-game log the scripts read from UNCORK_GAME_LOG.
        // A diagnostic relaunch also raises the Wine log level (UNCORK_DIAGNOSTIC=1),
        // so the log captures Wine's own errors, not just the game's output.
        var base = ["UNCORK_GAME_LOG": GameLog.path(for: game)]
        if diagnostic { base["UNCORK_DIAGNOSTIC"] = "1" }
        // Fullscreen-safe (virtual desktop): pass the screen size so the launch
        // scripts wrap the game in a screen-sized Wine desktop. Applies to any store.
        if UserOverrides.shared.virtualDesktop(game.launchID) { base["UNCORK_DESKTOP"] = screenWxH() }
        switch game.source {
        case .steam: return process("play.sh", [game.launchID], env: base)
        case .epic:  return process("epic.sh", ["launch", game.launchID, "--skip-version-check"],
                                    env: base.merging(compatEnv(game)) { _, b in b })
        case .gog:
            // gog.sh launch <install_path> <id>: direct-launches the exe on D3DMetal.
            let path = Paths.data + "/bottles/gog/drive_c/GOG Games/" + game.installDir
            return process("gog.sh", ["launch", path, game.launchID],
                           env: base.merging(compatEnv(game)) { _, b in b })
        case .custom:
            guard let exe = game.exePath else { return nil }
            // Native Mac game → run the .app directly (no Wine, no bottle).
            if game.hasMac { return process("run-mac.sh", [exe, game.launchID], env: base) }
            return process("run-exe.sh", [exe, game.launchID],
                           env: base.merging(["BOTTLE_NAME": game.bottle ?? "steam"]) { _, b in b })
        }
    }

    /// Main-screen size (points) as "WxH" for the Wine virtual desktop; a safe 16:9
    /// default if it can't be read.
    private static func screenWxH() -> String {
        guard let s = NSScreen.main else { return "1920x1080" }
        return "\(Int(s.frame.width))x\(Int(s.frame.height))"
    }

    /// Per-game compatibility env for Epic/GOG launches, from the user's overrides:
    /// backend choice (UNCORK_BACKEND, only when explicitly D3DMetal/DXMT) and extra
    /// launch args (UNCORK_LAUNCH_ARGS). Steam gets these through play.sh + the DB.
    private static func compatEnv(_ game: InstalledGame) -> [String: String] {
        var env: [String: String] = [:]
        let b = UserOverrides.shared.backend(game.launchID)
        if b == "d3dmetal" || b == "dxmt" { env["UNCORK_BACKEND"] = b }
        let a = UserOverrides.shared.launchArgs(game.launchID)
        if !a.isEmpty { env["UNCORK_LAUNCH_ARGS"] = a }
        return env
    }

    private static func process(_ script: String, _ args: [String], env: [String: String] = [:]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/\(script)"] + args
        p.environment = Paths.scriptEnvironment(env)
        return p
    }

    /// Build the compatibility-option environment for a launcher, from the same
    /// UserOverrides store the per-game compat panel writes (keyed by launcher id,
    /// e.g. "origin"). Lets a launcher's engine + DLL overrides be picked in the UI
    /// and take effect on next launch (compat options on every launcher), without
    /// rebuilding. The launch scripts read these envs:
    /// origin.sh → ORIGIN_ENGINE; every script honours WINEDLLOVERRIDES.
    static func launcherEnv(_ id: String) -> [String: String] {
        var env: [String: String] = [:]
        let engine = UserOverrides.shared.profile(id)          // "" / engine id
        if !engine.isEmpty, engine != "auto" {
            if id == "origin" { env["ORIGIN_ENGINE"] = engine }
        }
        let dll = UserOverrides.shared.dllOverridesString(id)  // "d3d11=b;dxgi=b"
        if !dll.isEmpty { env["WINEDLLOVERRIDES"] = dll }
        return env
    }

    /// Launch a user-added custom store: native .app directly (run-mac.sh) or its
    /// Windows client in its own bottle (run-exe.sh). Mirrors how games launch.
    static func launchCustomStore(_ e: CustomStoresStore.Entry) {
        if e.isMac {
            run(script: "run-mac.sh", args: [e.launchPath, e.id])
        } else {
            var args = [e.launchPath, e.id]
            if let flags = e.launchFlags, !flags.isEmpty { args += flags.split(separator: " ").map(String.init) }
            var env = ["BOTTLE_NAME": e.bottle ?? "custom-store-\(e.id)"]
            if let eng = e.engine, !eng.isEmpty { env["UNCORK_ENGINE"] = eng }   // run on the chosen Wine version
            run(script: "run-exe.sh", args: args, env: env)
        }
    }

    /// Launch a generic store template (built-in like Battle.net, or developer/
    /// imported) from its own bottle ("template-<id>") on the recipe's Wine version,
    /// using its configured launch_path + launch flags. Native templates run their
    /// .app directly.
    static func launchTemplate(_ t: StoreTemplate) {
        let bottle = "template-\(t.id)"
        if t.isMac {
            // Native template (itch.io): find the installed .app in the per-user apps
            // dir by glob (its name can vary, e.g. itch ships "Install itch.app").
            let dir = Paths.data + "/apps/\(t.id)"
            let appName = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
                .first { $0.hasSuffix(".app") } ?? t.launchPath
            run(script: "run-mac.sh", args: [dir + "/" + appName, t.id])
        } else {
            let exe = Paths.data + "/bottles/\(bottle)/drive_c/" + t.launchPath
            var args = [exe, t.id] + t.recipe.launchFlags
            var env = ["BOTTLE_NAME": bottle]
            if !t.recipe.engine.isEmpty, t.recipe.engine != "wine-stable", t.recipe.engine != "default" {
                env["UNCORK_ENGINE"] = t.recipe.engine
            }
            run(script: "run-exe.sh", args: args, env: env)
        }
    }

    /// Launch the Steam client on its own.
    static func launchSteam() { run(script: "steam.sh", args: [], env: launcherEnv("steam")) }

    /// Launch EA's legacy Origin client (its own window) on its own. Origin is used
    /// instead of the EA app because the EA app hangs on its localhost gRPC
    /// background-service handshake under Wine (see origin.sh / grpc-localhost docs).
    static func launchOrigin() { run(script: "origin.sh", args: ["launch"], env: launcherEnv("origin")) }

    /// Launch the modern EA app (kept for experimentation; blocked on the gRPC
    /// BGS handshake: Origin is the shipping EA client). See ea.sh.
    static func launchEA() { run(script: "ea.sh", args: ["launch"]) }

    /// Launch the Ubisoft Connect client (CEF): runs on the CrossOver CEF engine.
    /// Launched via NSTask (GUI context) so the CEF window presents.
    static func launchUbisoft() { run(script: "ubisoft.sh", args: ["launch"], env: launcherEnv("ubisoft")) }

    /// Install a game's required runtime components (winetricks verbs, e.g.
    /// dotnet40) into the bottle: automated + ngen-safe via install-runtime.sh.
    /// Fire-and-forget; the install runs for several minutes in the background.
    static func installComponents(_ verbs: [String], for game: InstalledGame) {
        guard !verbs.isEmpty else { return }
        ActivityStore.shared.show("Installing \(verbs.joined(separator: ", ")) for \(game.title)…", seconds: 8)
        // Target this game's bottle (isolated games get their own; others share "steam").
        run(script: "install-runtime.sh", args: verbs, env: ["BOTTLE_NAME": game.bottle ?? "steam"])
    }

    /// Uninstall an installed store game (deletes its downloaded files): Epic via
    /// legendary, GOG by removing its install dir. Refreshes the Library after.
    static func uninstall(_ game: InstalledGame) {
        let script: String, args: [String]
        switch game.source {
        case .epic: script = "epic.sh"; args = ["uninstall", game.launchID, "--yes"]
        case .gog:  script = "gog.sh";  args = ["uninstall", game.launchID]
        default: return   // Steam is managed by its client; custom games use "Remove from Library"
        }
        ActivityStore.shared.show("Uninstalling \(game.title)…", seconds: 6)
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["\(Paths.scripts)/\(script)"] + args
            p.environment = Paths.scriptEnvironment([:])
            try? p.run(); p.waitUntilExit()
            DispatchQueue.main.async {
                ActivityStore.shared.show("\(game.title) uninstalled")
                LibraryStore.shared.refresh()
            }
        }
    }

    /// Apply every compat-DB fix for a game (system DLL cleanup, folder strip,
    /// runtimes): what the "Apply fixes" button runs when a game won't launch.
    static func applyFixes(_ game: InstalledGame) {
        guard game.source == .steam else { return }
        ActivityStore.shared.show("Applying fixes for \(game.title)…", seconds: 6)
        run(script: "apply-fixes.sh", args: [game.launchID])
    }

    private static func run(script: String, args: [String], env: [String: String] = [:]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["\(Paths.scripts)/\(script)"] + args
            p.environment = Paths.scriptEnvironment(env)   // payload + data dirs, plus site overrides
            do { try p.run() } catch { NSLog("Uncork launch failed: \(error)") }
        }
    }
}
