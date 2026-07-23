import Foundation
import Combine

/// Drives the first-run setup for a launcher: download the engine (Wine +
/// D3DMetal) → set the store up → hand off to launch. Streams verbose progress
/// (script `@@STEP@@ <pct> <msg>` lines + plain log lines) so the wizard shows
/// exactly what's happening, not a silent spinner.
final class SetupRunner: ObservableObject {
    static let shared = SetupRunner()

    enum Phase: Equatable { case idle, running, done, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fraction: Double = 0      // 0…1 across the whole setup
    @Published private(set) var message: String = ""
    @Published private(set) var logTail: [String] = []    // recent verbose lines
    @Published private(set) var store: String = ""

    private var proc: Process?

    /// Run `<store>` setup end-to-end: ensure-engine.sh, then setup-<store>.sh.
    /// The two scripts each report 0-100; we map engine→0-40%, store→40-100%.
    func run(store id: String) {
        guard phase != .running else { return }
        store = id
        phase = .running; fraction = 0; message = "Starting…"; logTail = []
        // Chain in the shell so both scripts stream through one pipe.
        let scripts = Paths.scripts
        // `sed -l` = line-buffered (macOS/BSD), so each phase streams live instead
        // of being buffered until the script ends (which looked stuck at 40%).
        // Built-in kinds (steam/epic/gog) use their own setup-<id>.sh; generic
        // templates (developer-added or imported "Run Template" recipes) go through
        // the shared setup-template.sh, which applies the recipe + installs.
        let isGeneric = StoreTemplates.shared.template(id)?.kind == .generic
        let setupCmd = isGeneric ? "\"\(scripts)/setup-template.sh\" \(id)" : "\"\(scripts)/setup-\(id).sh\""
        let script = """
        set -o pipefail
        bash "\(scripts)/ensure-engine.sh" 2>&1 | sed -l 's/^/@@ENGINE@@ /'
        bash \(setupCmd)   2>&1 | sed -l 's/^/@@STORE@@ /'
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script]
        p.environment = Paths.scriptEnvironment(["BOTTLE_NAME": id])
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let h = pipe.fileHandleForReading
        h.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            for raw in s.split(whereSeparator: \.isNewline) { self?.parse(String(raw)) }
        }
        p.terminationHandler = { [weak self] (proc: Process) in
            DispatchQueue.main.async {
                h.readabilityHandler = nil
                self?.proc = nil
                let ok = proc.terminationStatus == 0
                self?.phase = ok ? .done : .failed
                if ok { self?.fraction = 1; self?.message = "Ready" }
                else if (self?.message.isEmpty ?? true) { self?.message = "Setup failed" }
            }
        }
        proc = p
        do { try p.run() } catch { phase = .failed; message = "Couldn't start setup"; proc = nil }
    }

    /// Parse one output line. Engine steps map to 0-40% of the bar, store steps
    /// to 40-100%. Non-@@STEP@@ lines feed the verbose log tail.
    private func parse(_ line: String) {
        var seg = ""; var body = line
        if line.hasPrefix("@@ENGINE@@ ") { seg = "engine"; body = String(line.dropFirst(11)) }
        else if line.hasPrefix("@@STORE@@ ") { seg = "store"; body = String(line.dropFirst(10)) }

        if let r = body.range(of: "@@STEP@@ ") {
            let parts = body[r.upperBound...].split(separator: " ", maxSplits: 1)
            guard let pct = parts.first.flatMap({ Double($0) }) else { return }
            let msg = parts.count > 1 ? String(parts[1]) : ""
            let overall = seg == "engine" ? pct * 0.40 : 40 + pct * 0.60
            DispatchQueue.main.async {
                self.fraction = max(self.fraction, overall / 100)
                if !msg.isEmpty { self.message = msg }
            }
        } else {
            // Verbose log line (strip color codes): keep the last ~8.
            let clean = body.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, !clean.hasPrefix("---") else { return }
            DispatchQueue.main.async {
                self.logTail.append(String(clean.prefix(100)))
                if self.logTail.count > 8 { self.logTail.removeFirst(self.logTail.count - 8) }
            }
        }
    }

    func reset() { if phase != .running { phase = .idle; fraction = 0; message = ""; logTail = [] } }
}
