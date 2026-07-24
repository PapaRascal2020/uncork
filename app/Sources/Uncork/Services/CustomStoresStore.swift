import Foundation
import Combine
import SwiftUI

/// User-configured storefronts that aren't built-in templates (Steam/Epic/GOG).
/// A custom store is either installed by Uncork (run its installer in a fresh
/// Wine bottle for Windows, or a native macOS installer) or a shortcut to an
/// already-installed client. Persisted to custom-stores.json.
///
/// Games: best-effort: if the user gives a `gamesDir`, Uncork scans it for
/// launchable .exe/.app files and surfaces them in the Library.
final class CustomStoresStore: ObservableObject {
    static let shared = CustomStoresStore()

    struct Entry: Codable, Identifiable, Hashable {
        let id: String
        var name: String
        var platform: String      // "windows" (via Wine) | "mac" (native)
        var launchPath: String    // Windows: .exe path inside its bottle. Mac: the .app path.
        var bottle: String?       // Windows: its own bottle name. Mac: nil.
        var gamesDir: String?     // optional folder Uncork scans for this store's games
        var symbol: String = "bag.fill"
        var engine: String?       // Windows: chosen Wine engine/version (UNCORK_ENGINE); nil = default
        var winver: String?       // Windows version the bottle reports (win10/win7/…)
        var launchFlags: String?  // extra launch args
        var storeURL: String?     // optional web storefront to browse in-app (Browse sidebar)
        var isMac: Bool { platform == "mac" }
    }

    @Published private(set) var entries: [Entry] = []
    private let url: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("custom-stores.json")
        if let d = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Entry].self, from: d) { entries = list }
    }

    /// Custom stores as Launcher tiles for the Stores page (id = "custom-store:<id>").
    func launchers() -> [Launcher] {
        entries.map { e in
            Launcher(id: "custom-store:\(e.id)", name: e.name,
                     tagline: e.isMac ? "Custom store (native macOS)" : "Custom store (Windows via Wine)",
                     symbol: e.symbol,
                     artStart: Color(red: 0.16, green: 0.16, blue: 0.20),
                     artEnd: Color(red: 0.05, green: 0.05, blue: 0.07),
                     status: .installed,
                     runsVia: e.isMac ? "Native macOS app: runs directly, no Wine"
                                      : "Windows client in its own Wine bottle '\(e.bottle ?? "")'",
                     setupNote: "A store you added yourself. Launch it and manage its games in its own window."
                     + (e.gamesDir != nil ? " Uncork also scans its games folder for your Library." : ""),
                     platform: e.platform)
        }
    }

    func entry(forLauncherID lid: String) -> Entry? {
        guard lid.hasPrefix("custom-store:") else { return nil }
        let id = String(lid.dropFirst("custom-store:".count))
        return entries.first { $0.id == id }
    }

    /// Best-effort: scan each custom store's gamesDir for launchable titles so they
    /// appear in the Library. Windows stores → .exe (run via the store's bottle);
    /// Mac stores → .app (run natively). Skips obvious non-games (uninstallers etc.).
    func games() -> [InstalledGame] {
        var out: [InstalledGame] = []
        let fm = FileManager.default
        for s in entries {
            guard let dir = s.gamesDir, !dir.isEmpty,
                  let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            let ext = s.isMac ? "app" : "exe"
            for name in items where name.lowercased().hasSuffix(".\(ext)") {
                let low = name.lowercased()
                if low.contains("unins") || low.contains("setup") || low.contains("crashreport") || low.contains("redist") { continue }
                let path = dir + "/" + name
                out.append(InstalledGame(
                    source: .custom, launchID: "\(s.id)-\(name)".lowercased(),
                    title: (name as NSString).deletingPathExtension,
                    installDir: name, installed: true, exePath: path,
                    bottle: s.isMac ? nil : s.bottle,
                    platforms: s.isMac ? [.mac] : [.windows]))
            }
        }
        return out
    }

    @discardableResult
    func add(name: String, platform: String, launchPath: String, bottle: String?, gamesDir: String?,
             engine: String? = nil, winver: String? = nil, launchFlags: String? = nil,
             storeURL: String? = nil) -> Entry {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let e = Entry(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                      platform: platform == "mac" ? "mac" : "windows",
                      launchPath: launchPath,
                      bottle: platform == "mac" ? nil : (bottle ?? "custom-store-\(id)"),
                      gamesDir: (gamesDir?.isEmpty ?? true) ? nil : gamesDir,
                      engine: (engine?.isEmpty ?? true) ? nil : engine,
                      winver: (winver?.isEmpty ?? true) ? nil : winver,
                      launchFlags: (launchFlags?.isEmpty ?? true) ? nil : launchFlags,
                      storeURL: (storeURL?.isEmpty ?? true) ? nil : storeURL)
        entries.append(e); save()
        return e
    }

    func remove(id: String) { entries.removeAll { $0.id == id }; save() }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: url) }
    }
}

/// Runs install-custom-store.sh for a Windows custom store (fresh bottle + run the
/// installer), streaming @@STEP@@ progress and capturing the detected FOUND_EXE=
/// launch target. macOS custom stores skip this (they're a native .app shortcut).
final class CustomStoreInstaller: ObservableObject {
    static let shared = CustomStoreInstaller()

    @Published private(set) var installing = false
    @Published private(set) var fraction: Double = 0
    @Published private(set) var message = ""

    private var proc: Process?

    /// Install `installerPath` into `bottle` on the chosen Wine `engine` + Windows
    /// version `winver`; onDone(foundExeUnixPath?): nil on failure.
    func install(bottle: String, installerPath: String, engine: String, winver: String,
                 onDone: @escaping (String?) -> Void) {
        guard !installing else { return }
        installing = true; fraction = 0; message = "Starting…"
        var foundExe: String? = nil
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/install-custom-store.sh", bottle, installerPath, winver]
        var env = ["BOTTLE_NAME": bottle]
        if !engine.isEmpty, engine != "wine-stable", engine != "default" { env["UNCORK_ENGINE"] = engine }
        p.environment = Paths.scriptEnvironment(env)
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let h = pipe.fileHandleForReading
        h.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            for raw in s.split(whereSeparator: \.isNewline) {
                let line = String(raw)
                if let r = line.range(of: "FOUND_EXE=") { foundExe = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
                else if let r = line.range(of: "@@STEP@@ ") {
                    let parts = line[r.upperBound...].split(separator: " ", maxSplits: 1)
                    if let pct = parts.first.flatMap({ Double($0) }) {
                        let msg = parts.count > 1 ? String(parts[1]) : ""
                        DispatchQueue.main.async { self?.fraction = max(self?.fraction ?? 0, pct/100); if !msg.isEmpty { self?.message = msg } }
                    }
                }
            }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                h.readabilityHandler = nil
                self?.proc = nil; self?.installing = false
                let ok = proc.terminationStatus == 0
                self?.message = ok ? "Ready" : "Install failed"
                onDone(ok ? foundExe : nil)
            }
        }
        proc = p
        do { try p.run() } catch { installing = false; message = "Couldn't start"; onDone(nil) }
    }
}
