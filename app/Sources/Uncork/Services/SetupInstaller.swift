import Foundation
import Combine

/// Installs a Setup-page graphics component on demand by running the matching
/// ensure-* script and streaming its @@STEP@@ progress to the Setup buttons.
/// Wine (and DXMT, which ships inside it) come from ensure-wine-engine.sh; DXVK
/// from ensure-cli.sh; D3DMetal from ensure-engine.sh.
final class SetupInstaller: ObservableObject {
    static let shared = SetupInstaller()

    @Published private(set) var installing: String? = nil   // install kind in progress
    @Published private(set) var fraction: Double = 0
    @Published private(set) var message = ""

    private func command(for kind: String) -> (String, [String])? {
        switch kind {
        case "wine": return ("ensure-wine-engine.sh", ["wine-stable"])
        case "dxvk": return ("ensure-cli.sh", ["dxvk"])
        case "gptk": return ("ensure-engine.sh", [])
        default:     return nil
        }
    }

    func install(_ kind: String, onDone: @escaping () -> Void) {
        guard installing == nil, let (script, args) = command(for: kind) else { return }
        installing = kind; fraction = 0; message = "Starting…"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/\(script)"] + args
        p.environment = Paths.scriptEnvironment()
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let h = pipe.fileHandleForReading
        h.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            for raw in s.split(whereSeparator: \.isNewline) {
                let line = String(raw)
                guard let r = line.range(of: "@@STEP@@ ") else { continue }
                let parts = line[r.upperBound...].split(separator: " ", maxSplits: 1)
                guard let pct = parts.first.flatMap({ Double($0) }) else { continue }
                let msg = parts.count > 1 ? String(parts[1]) : ""
                DispatchQueue.main.async {
                    self?.fraction = max(self?.fraction ?? 0, pct / 100)
                    if !msg.isEmpty { self?.message = msg }
                }
            }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                h.readabilityHandler = nil
                self?.installing = nil; self?.fraction = 0; self?.message = ""
                ActivityStore.shared.show(proc.terminationStatus == 0 ? "Installed" : "Install failed")
                onDone()
            }
        }
        do { try p.run() } catch {
            installing = nil; ActivityStore.shared.show("Couldn't start the install"); onDone()
        }
    }
}
