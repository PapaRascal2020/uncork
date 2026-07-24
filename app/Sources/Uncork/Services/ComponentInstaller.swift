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
            ? "Downloading and installing .NET… several minutes on first run, and it may look paused while it extracts (that's normal)."
            : "Starting…"
        ActivityStore.shared.show("Installing \(verb)…", seconds: 4)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/install-runtime.sh", verb]
        p.environment = Paths.scriptEnvironment(["BOTTLE_NAME": bottle, "PYTHONUNBUFFERED": "1"])

        // .NET installs scroll winetricks internals (winver tokens like "win10",
        // per-file "Preparing:" lines) and then go SILENT for minutes while the
        // installer downloads/extracts, which froze the status on a meaningless
        // token. For dotnet verbs keep the honest static message (the spinner shows
        // liveness); for others show the last genuinely meaningful line.
        let isDotnet = verb.hasPrefix("dotnet")
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            // Two kinds of update per chunk: a "@@STEP@@ <pct> <label>" progress line
            // (the .NET download watcher) always wins; otherwise, for non-.NET verbs,
            // the last genuinely meaningful line. .NET's raw winetricks lines are
            // dropped (they scroll then freeze), so its status is the static message
            // plus the download percentage.
            let noise = ["warning:", "wine:", "fixme:", "err:", "running ", "executing ", "preparing:", "using winetricks", "x connection"]
            let winvers: Set<String> = ["win10", "win11", "win7", "win8", "win81", "winxp", "winxp64", "winvista", "win2k3"]
            var stepMsg: String?
            var lineMsg: String?
            for raw in s.split(whereSeparator: \.isNewline) {
                let line = String(raw)
                if let r = line.range(of: "@@STEP@@ ") {
                    let parts = line[r.upperBound...].split(separator: " ", maxSplits: 1)
                    let pct = parts.first.flatMap { Int($0) }
                    let label = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                    if !label.isEmpty { stepMsg = pct.map { "\(label) \($0)%" } ?? label }
                    continue
                }
                if isDotnet { continue }
                let t = line.trimmingCharacters(in: .whitespaces).lowercased()
                if t.isEmpty || t.hasPrefix("---") || winvers.contains(t) { continue }
                if t.contains("/users/") || t.contains("/library/") || t.contains("application support") { continue }
                if noise.contains(where: { t.hasPrefix($0) }) { continue }
                lineMsg = String(line.prefix(90))
            }
            guard let msg = stepMsg ?? lineMsg else { return }   // nothing new → keep current
            DispatchQueue.main.async { self?.lastLine[k] = msg }
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
