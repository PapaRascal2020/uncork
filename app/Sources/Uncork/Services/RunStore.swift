import Foundation
import Combine

/// Tracks the live run-state of each game so the Play button can show
/// Play → Launching… → Launched, return to Play on exit, or show a clear
/// "Didn't start" state if the game never appears.
enum RunState: Equatable { case idle, launching, running, failed }

final class RunStore: ObservableObject {
    static let shared = RunStore()
    @Published private(set) var states: [String: RunState] = [:]
    /// Live launch status streamed from the launch script (e.g. "Signing in to
    /// Steam…", "Launching Death Squared…") so the button isn't silent.
    @Published private(set) var launchMessage: [String: String] = [:]

    private var patterns: [String: String] = [:]   // game id -> process-match string
    private var deadline: [String: Date] = [:]       // how long to wait for it to appear
    private var launchProcs: [String: Process] = [:] // the running launch script
    private var missStreak: [String: Int] = [:]      // consecutive "not running" polls (debounce)
    private var timer: Timer?

    /// Once the launch script has finished (it backgrounds the game and exits),
    /// the game gets this long to show a process before it counts as a failed start.
    /// The countdown doesn't run while the script is still running (Steam sign-in
    /// can take a minute), so a slow launch never false-fails. Generous, because a
    /// first launch can compile shaders / have Steam decrypt before a window shows.
    private let appearWindow: TimeInterval = 240
    /// Number of consecutive "not running" polls before a running game is treated
    /// as closed. Debounces the brief gap when a launcher process hands off to the
    /// real game exe (which otherwise looked like "closed" → button flipped to Play).
    private let missThreshold = 4   // ~10s at the 2.5s poll interval

    func state(_ id: String) -> RunState { states[id] ?? .idle }
    func status(_ id: String) -> String? { launchMessage[id] }

    func launch(_ game: InstalledGame, diagnostic: Bool = false) {
        let id = game.id
        states[id] = .launching
        launchMessage[id] = diagnostic ? "Starting (diagnostic)…" : "Starting…"
        patterns[id] = game.installDir.isEmpty ? game.title : game.installDir
        deadline[id] = nil   // don't count down while the launch script runs

        guard let p = LaunchService.launchProcess(for: game, diagnostic: diagnostic) else {
            states[id] = .failed; launchMessage[id] = "Couldn't start the launcher"; return
        }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            for raw in s.split(whereSeparator: \.isNewline) {
                let line = String(raw)
                var msg: String? = nil
                if let r = line.range(of: "@@STATUS@@ ") {
                    msg = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                } else if let r = line.range(of: "@@STEP@@ ") {
                    // Progress from a long step the launch triggers (e.g. a slim
                    // install re-fetching its DirectX engine, or first-use game
                    // libraries): "@@STEP@@ <pct> <label>". Show "label pct%" so the
                    // button reflects a ~400 MB download instead of looking stalled.
                    let parts = line[r.upperBound...].split(separator: " ", maxSplits: 1)
                    let pct = parts.first.flatMap { Int($0) }
                    let label = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                    if !label.isEmpty {
                        msg = (pct.map { $0 > 0 && $0 < 100 ? "\(label) \($0)%" : label }) ?? label
                    }
                }
                guard let m = msg, !m.isEmpty else { continue }
                DispatchQueue.main.async {
                    guard self?.states[id] == .launching else { return }
                    self?.launchMessage[id] = m
                    // Keep the toast spinner + live status visible through the whole
                    // launch: each line re-arms it, so it doesn't vanish after a few
                    // seconds while Steam signs in / the game decrypts / an engine
                    // downloads.
                    ActivityStore.shared.show(m, seconds: 20)
                }
            }
        }
        p.terminationHandler = { [weak self] (proc: Process) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                handle.readabilityHandler = nil
                self.launchProcs[id] = nil
                // Epic/custom scripts stay attached to the game; if it's already
                // detected running, leave it. Otherwise: exit 0 = script launched
                // and backgrounded the game (Steam) → start the appear window;
                // exit ≠ 0 = the launch itself failed.
                guard self.states[id] == .launching else { return }
                if proc.terminationStatus == 0 {
                    self.launchMessage[id] = "Almost there, waiting for the game to open (first launch can take a while)…"
                    self.deadline[id] = Date().addingTimeInterval(self.appearWindow)
                } else {
                    self.states[id] = .failed
                    if (self.launchMessage[id] ?? "").isEmpty { self.launchMessage[id] = "Launch failed" }
                }
            }
        }
        launchProcs[id] = p
        do { try p.run() } catch {
            states[id] = .failed; launchProcs[id] = nil; launchMessage[id] = "Couldn't start the launcher"; return
        }
        startTimer()
    }

    /// Force-quit a running (or stuck-launching) game.
    ///
    /// Safety: this stops only the game's Wine prefix via `wineserver -k`
    /// (scripts/stop.sh), never `pkill -f <name>`, which matches a short
    /// human string against every process on the system and can kill unrelated
    /// macOS apps (browser, terminal). `wineserver -k` never leaves the bottle.
    func stop(_ game: InstalledGame) {
        ActivityStore.shared.show("Stopping \(game.title)…")
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            // Native Mac game → quit it by its own install path (no Wine prefix to
            // kill); Windows games → the bottle-scoped stop.sh.
            if game.hasMac, game.source == .custom, let exe = game.exePath {
                p.arguments = ["\(Paths.scripts)/stop-mac.sh", exe]
                p.environment = Paths.scriptEnvironment()
            } else {
            p.arguments = ["\(Paths.scripts)/stop.sh"]
            p.environment = Paths.scriptEnvironment([
                "BOTTLE_NAME": game.bottleName,
                "SOURCE": game.source.rawValue,      // Steam → game-only stop
                "LAUNCH_ID": game.launchID,          // resolves the game's install dir
            ])
            }
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            DispatchQueue.main.async {
                self.states[game.id] = .idle
                self.patterns[game.id] = nil
                self.deadline[game.id] = nil
                self.missStreak[game.id] = nil
                PlaytimeStore.shared.ended(game.id)   // count the session we just stopped
            }
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        // Only launching/running games need polling; idle/failed are terminal.
        let active = states.filter { $0.value == .launching || $0.value == .running }
        if active.isEmpty { timer?.invalidate(); timer = nil; return }
        let pats = patterns
        DispatchQueue.global(qos: .utility).async {
            var running: [String: Bool] = [:]
            for (id, _) in active { running[id] = RunStore.isRunning(pats[id] ?? "") }
            DispatchQueue.main.async { self.apply(running) }
        }
    }

    private func apply(_ running: [String: Bool]) {
        for (id, isRun) in running {
            switch states[id] ?? .idle {
            case .launching:
                if isRun {
                    states[id] = .running; launchMessage[id] = nil            // window is up
                    missStreak[id] = 0
                    PlaytimeStore.shared.began(id)                            // start timing the session
                    ActivityStore.shared.show("\(shortTitle(id)) is running", seconds: 2)
                } else if let d = deadline[id], Date() > d {   // only after the script exited
                    states[id] = .failed                     // never appeared → didn't start
                    launchMessage[id] = nil
                    ActivityStore.shared.error("\(shortTitle(id)) didn't start: open its page → Compatibility")
                } else if let msg = launchMessage[id], !msg.isEmpty {
                    // Still launching (Steam signing in, or the game decrypting/loading
                    // after the script exited). Re-arm the bottom pill each tick so it
                    // stays visible for the whole launch instead of lapsing after the
                    // last status line, which read as "nothing is happening".
                    ActivityStore.shared.show(msg, seconds: 6)
                }
            case .running:
                if isRun {
                    missStreak[id] = 0                                        // still running
                } else {
                    // Debounce: a single missed poll can be the launcher→game
                    // handoff, not a real exit. Only go back to Play after several
                    // consecutive misses.
                    let m = (missStreak[id] ?? 0) + 1
                    missStreak[id] = m
                    if m >= missThreshold {
                        states[id] = .idle; launchMessage[id] = nil; missStreak[id] = nil
                        PlaytimeStore.shared.ended(id)                        // accumulate playtime
                    }
                }
            case .idle, .failed:
                break
            }
        }
    }

    private func shortTitle(_ id: String) -> String { String(id.split(separator: ":").last ?? "Game") }

    static func isRunning(_ pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }
}
