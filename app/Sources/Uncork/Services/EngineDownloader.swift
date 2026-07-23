import Foundation
import Combine

/// Downloads a compatibility profile's engine on demand (scripts/ensure-profile.sh),
/// the Steam-style "get this engine version" action. Streams @@STEP@@ progress
/// so the detail page can show a real bar instead of a silent wait.
final class EngineDownloader: ObservableObject {
    static let shared = EngineDownloader()

    @Published private(set) var installing: String = ""   // profile id, "" when idle
    @Published private(set) var fraction: Double = 0
    @Published private(set) var message: String = ""

    private var proc: Process?

    var isBusy: Bool { !installing.isEmpty }

    /// Download the engine for `profileID`. `onDone(true)` on success.
    func download(profileID: String, onDone: @escaping (Bool) -> Void) {
        guard installing.isEmpty else { return }
        installing = profileID; fraction = 0; message = "Starting…"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/ensure-profile.sh", profileID]
        p.environment = Paths.scriptEnvironment()
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
                self?.fraction = ok ? 1 : (self?.fraction ?? 0)
                self?.installing = ""
                self?.message = ok ? "Ready" : "Download failed"
                onDone(ok)
            }
        }
        proc = p
        do { try p.run() } catch { installing = ""; message = "Couldn't start download"; onDone(false) }
    }

    private func parse(_ line: String) {
        guard let r = line.range(of: "@@STEP@@ ") else { return }
        let parts = line[r.upperBound...].split(separator: " ", maxSplits: 1)
        guard let pct = parts.first.flatMap({ Double($0) }) else { return }
        let msg = parts.count > 1 ? String(parts[1]) : ""
        DispatchQueue.main.async {
            self.fraction = max(self.fraction, pct / 100)
            if !msg.isEmpty { self.message = msg }
        }
    }
}
