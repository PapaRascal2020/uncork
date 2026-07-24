import Foundation
import Combine

/// Runs winetricks component installs (install-runtime.sh) and tracks their state
/// so the Components UI shows Installing → Installed / Failed instead of a spinner
/// that never resolves. Streams the script's output so the install isn't silent.
final class ComponentInstaller: ObservableObject {
    static let shared = ComponentInstaller()

    enum State: Equatable { case installing, done, failed }

    @Published private(set) var states: [String: State] = [:]   // "bottle:verb" -> state
    @Published private(set) var lastLine: [String: String] = [:] // latest output line
    private var procs: [String: Process] = [:]

    private func key(_ bottle: String, _ verb: String) -> String { "\(bottle):\(verb)" }
    func state(_ bottle: String, _ verb: String) -> State? { states[key(bottle, verb)] }
    func progress(_ bottle: String, _ verb: String) -> String { lastLine[key(bottle, verb)] ?? "Starting…" }

    func install(verb: String, bottle: String) {
        let k = key(bottle, verb)
        guard procs[k] == nil else { return }
        states[k] = .installing
        // .NET installs are slow (the NGen optimizer) and go silent for minutes, so
        // set an honest expectation up front instead of a raw log line that freezes.
        lastLine[k] = verb.hasPrefix("dotnet")
            ? "Installing… .NET can take several minutes and may look paused (that's normal)."
            : "Starting…"
        ActivityStore.shared.show("Installing \(verb)…", seconds: 4)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/install-runtime.sh", verb]
        p.environment = Paths.scriptEnvironment(["BOTTLE_NAME": bottle, "PYTHONUNBUFFERED": "1"])

        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            // Keep the last MEANINGFUL line for a live status: drop winetricks/Wine
            // internals (warnings, fixme/err channels, raw paths, "Running/Executing
            // <wine>") that read as noise and would freeze on a stray warning.
            let noise = ["warning:", "wine:", "fixme:", "err:", "running ", "executing ", "using winetricks", "x connection"]
            let lines = s.split(whereSeparator: \.isNewline).map(String.init).filter { raw in
                let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if t.isEmpty || t.hasPrefix("---") { return false }
                if t.contains("/users/") || t.contains("/library/") || t.contains("application support") { return false }
                return !noise.contains { t.hasPrefix($0) }
            }
            guard let line = lines.last else { return }   // nothing meaningful → keep the current message
            DispatchQueue.main.async { self?.lastLine[k] = String(line.prefix(90)) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                handle.readabilityHandler = nil
                let ok = proc.terminationStatus == 0
                self?.states[k] = ok ? .done : .failed
                self?.procs[k] = nil
                ActivityStore.shared.show(ok ? "\(verb) installed ✓" : "\(verb) install failed")
            }
        }
        procs[k] = p
        do { try p.run() } catch { states[k] = .failed; procs[k] = nil }
    }
}
