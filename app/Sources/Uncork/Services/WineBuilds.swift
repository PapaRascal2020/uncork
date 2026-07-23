import Foundation
import Combine

/// A downloadable standalone Wine build (whole runtime tree), shown in the Wine
/// Manager's "Wine Builds" tab. Loaded from wine-fixes/wine-builds.json so the
/// catalog updates without an app rebuild. Installed via ensure-wine-build.sh into
/// the writable per-user engine dir.
struct WineBuild: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let channel: String     // stable | staging | devel | crossover | gptk
    let url: String
    let sizeMB: Int
    let dxmt: Bool
    let summary: String
    let notes: String
}

/// Loads + caches wine-fixes/wine-builds.json.
final class WineBuildsCatalog {
    static let shared = WineBuildsCatalog()
    private(set) var all: [WineBuild] = []

    private init() { reload() }

    func reload() {
        let path = Paths.payload + "/wine-fixes/wine-builds.json"
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let builds = root["builds"] as? [String: [String: Any]]
        else { all = []; return }
        // Order: stable, staging, devel, then the rest.
        let chOrder: [String: Int] = ["stable": 0, "staging": 1, "devel": 2, "crossover": 3, "gptk": 4]
        let list: [WineBuild] = builds.map { (id, b) in
            WineBuild(id: id,
                      name: (b["name"] as? String) ?? id,
                      version: (b["version"] as? String) ?? "",
                      channel: (b["channel"] as? String) ?? "",
                      url: (b["url"] as? String) ?? "",
                      sizeMB: (b["size_mb"] as? Int) ?? 0,
                      dxmt: (b["dxmt"] as? Bool) ?? false,
                      summary: (b["summary"] as? String) ?? "",
                      notes: (b["notes"] as? String) ?? "")
        }
        all = list.sorted { a, b in
            let ra = chOrder[a.channel] ?? 9
            let rb = chOrder[b.channel] ?? 9
            if ra != rb { return ra < rb }
            return a.name < b.name
        }
    }

    /// Installed when its wine binary exists in the writable engine dir.
    func isInstalled(_ b: WineBuild) -> Bool {
        FileManager.default.isExecutableFile(atPath: Paths.data + "/engine/wine-builds/\(b.id)/bin/wine")
    }
}

/// Downloads a standalone Wine build on demand (scripts/ensure-wine-build.sh),
/// streaming @@STEP@@ progress: the "Wine Builds" analog of EngineDownloader.
final class WineBuildInstaller: ObservableObject {
    static let shared = WineBuildInstaller()

    @Published private(set) var installing: String = ""   // build id, "" when idle
    @Published private(set) var fraction: Double = 0
    @Published private(set) var message: String = ""

    var isBusy: Bool { !installing.isEmpty }
    private var proc: Process?

    func download(buildID: String, onDone: @escaping (Bool) -> Void) {
        guard installing.isEmpty else { return }
        installing = buildID; fraction = 0; message = "Starting…"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/ensure-wine-build.sh", buildID]
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
