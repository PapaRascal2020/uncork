import Foundation

/// One compatibility profile: a matched (Wine engine + graphics backend) bundle,
/// the Mac analog of a Steam/Proton version. Loaded from compat/profiles.json so
/// the catalog updates without rebuilding the app.
struct CompatProfile: Identifiable, Hashable {
    let id: String          // "auto", "gptk", "wine11-dxmt", "wine11-dxvk", …
    let label: String
    let backend: String     // "", "d3dmetal", "dxmt", "dxvk"
    let bundled: Bool
    let summary: String
    let bestFor: String
    let warn: String?       // caveat shown in the UI (e.g. DXVK geometryShader)
    let engineID: String    // "" = no downloadable engine (bundled Wine 11 / auto)
    let download: String    // download URL, "" if none

    /// A downloadable engine that isn't on disk yet (needs a first-use download).
    var needsDownload: Bool { !engineID.isEmpty && !download.isEmpty }
}

/// Loads and caches compat/profiles.json (the profile catalog).
final class CompatProfiles {
    static let shared = CompatProfiles()
    private(set) var all: [CompatProfile] = []
    private(set) var defaultID = "auto"

    private init() { reload() }

    func reload() {
        let path = Paths.payload + "/compat/profiles.json"
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [String: [String: Any]]
        else { all = fallback(); return }
        defaultID = (root["default"] as? String) ?? "auto"
        // Preserve a sensible display order (auto first, then the rest as listed).
        let order = ["auto", "gptk", "wine11-dxmt", "wine11-dxvk"]
        let ids = order.filter { profiles[$0] != nil } + profiles.keys.filter { !order.contains($0) }.sorted()
        all = ids.compactMap { id in
            guard let p = profiles[id] else { return nil }
            return CompatProfile(
                id: id,
                label: (p["label"] as? String) ?? id,
                backend: (p["backend"] as? String) ?? "",
                bundled: (p["bundled"] as? Bool) ?? true,
                summary: (p["summary"] as? String) ?? "",
                bestFor: (p["best_for"] as? String) ?? "",
                warn: p["warn"] as? String,
                engineID: (p["engine_id"] as? String) ?? "",
                download: (p["download"] as? String) ?? "")
        }
        if all.isEmpty { all = fallback() }
    }

    func profile(_ id: String) -> CompatProfile? { all.first { $0.id == id } }

    /// True when the profile's engine is present on disk (bundled profiles and
    /// non-engine ones are always "installed"; downloadable GPTk versions are
    /// checked in the writable per-user engine dir).
    func isEngineInstalled(_ p: CompatProfile) -> Bool {
        guard !p.engineID.isEmpty else { return true }
        let wine64 = Paths.data + "/engine/\(p.engineID)/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
        return FileManager.default.isExecutableFile(atPath: wine64)
    }

    /// Hard-coded fallback so the picker still works if the JSON is missing.
    private func fallback() -> [CompatProfile] {
        [CompatProfile(id: "auto", label: "Automatic (recommended)", backend: "", bundled: true,
                       summary: "Let Uncork choose the best engine.", bestFor: "Most games.", warn: nil,
                       engineID: "", download: "")]
    }
}
