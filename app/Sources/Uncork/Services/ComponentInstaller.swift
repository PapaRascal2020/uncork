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
        lastLine[k] = "Starting…"
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
            // Keep the last meaningful line (skip blank/rule lines) for a live status.
            let lines = s.split(whereSeparator: \.isNewline).map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("---") }
            guard let line = lines.last else { return }
            DispatchQueue.main.async { self?.lastLine[k] = String(line.prefix(80)) }
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
