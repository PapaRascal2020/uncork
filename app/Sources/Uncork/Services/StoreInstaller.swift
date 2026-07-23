import Foundation
import Combine

/// Runs a store's first-run bootstrap script (e.g. setup-steam.sh) and streams
/// its `@@STEP@@ <pct> <message>` progress into the UI, so "Add a Store" shows a
/// live install bar instead of a silent spinner.
final class StoreInstaller: ObservableObject {
    static let shared = StoreInstaller()

    enum Phase: Equatable { case idle, installing, done, failed }

    struct Status: Equatable {
        var phase: Phase = .idle
        var fraction: Double = 0     // 0…1
        var message: String = ""
    }

    @Published private(set) var statuses: [String: Status] = [:]   // store id -> status
    private var procs: [String: Process] = [:]
    private var lastError: [String: String] = [:]

    func status(_ id: String) -> Status { statuses[id] ?? Status() }
    func isInstalling(_ id: String) -> Bool { statuses[id]?.phase == .installing }

    /// Which stores have an automated bootstrap script today.
    static func canInstall(_ id: String) -> Bool { script(for: id) != nil }

    private static func script(for id: String) -> String? {
        switch id {
        case "steam": return "setup-steam.sh"
        default:      return nil
        }
    }

    /// Start (or restart) a store's bootstrap.
    func install(store id: String) {
        guard procs[id] == nil, let script = Self.script(for: id) else { return }
        statuses[id] = Status(phase: .installing, fraction: 0.02, message: "Starting…")
        lastError[id] = nil
        ActivityStore.shared.show("Installing \(id.capitalized)…", seconds: 4)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/\(script)"]
        p.environment = Paths.scriptEnvironment(["BOTTLE_NAME": id])

        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            self?.parse(id: id, chunk: s)
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                handle.readabilityHandler = nil
                self?.procs[id] = nil
                let ok = proc.terminationStatus == 0
                var st = self?.statuses[id] ?? Status()
                st.phase = ok ? .done : .failed
                if ok { st.fraction = 1; st.message = "Done" }
                else { st.message = self?.lastError[id] ?? "Install failed" }
                self?.statuses[id] = st
                ActivityStore.shared.show(ok ? "\(id.capitalized) installed ✓" : "\(id.capitalized) install failed")
                if ok { StoreRegistry.shared.refresh() }
            }
        }
        procs[id] = p
        do { try p.run() } catch {
            statuses[id] = Status(phase: .failed, fraction: 0, message: "Couldn't start the installer")
            procs[id] = nil
        }
    }

    private func parse(id: String, chunk: String) {
        for raw in chunk.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if let r = line.range(of: "@@STEP@@ ") {
                let parts = line[r.upperBound...].split(separator: " ", maxSplits: 1)
                guard let pct = parts.first.flatMap({ Double($0) }) else { continue }
                let msg = parts.count > 1 ? String(parts[1]) : ""
                DispatchQueue.main.async {
                    var st = self.statuses[id] ?? Status()
                    st.phase = .installing
                    st.fraction = max(st.fraction, pct / 100)   // never go backwards
                    if !msg.isEmpty { st.message = msg }
                    self.statuses[id] = st
                }
            } else if let r = line.range(of: "✗ ") {
                // die() prints "✗ <reason>": keep the last one for the failure message.
                lastError[id] = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
