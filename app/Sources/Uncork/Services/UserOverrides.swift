import Foundation

/// Per-user, per-game toggles (e.g. the Metal performance overlay), persisted to
/// ~/Library/Application Support/Uncork/overrides.json: the same file the shell
/// scripts (compatdb.sh) read. So a toggle flipped in the UI takes effect on the
/// next launch without touching the shipped compat DB or rebuilding the app.
final class UserOverrides {
    static let shared = UserOverrides()
    private let url: URL
    private var data: [String: [String: Any]] = [:]

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("overrides.json")
        if let d = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] {
            data = obj
        }
    }

    private func save() {
        guard let d = try? JSONSerialization.data(withJSONObject: data,
                                                  options: [.prettyPrinted, .sortedKeys]) else { return }
        try? d.write(to: url)
    }

    func hud(_ appid: String) -> Bool { (data[appid]?["hud"] as? Bool) ?? false }
    func setHUD(_ appid: String, _ on: Bool) {
        var g = data[appid] ?? [:]; g["hud"] = on; data[appid] = g; save()
    }

    /// Windows version Wine reports for this game ("" = automatic/default).
    func winver(_ appid: String) -> String { (data[appid]?["winver"] as? String) ?? "" }
    func setWinver(_ appid: String, _ v: String) {
        var g = data[appid] ?? [:]
        if v.isEmpty { g.removeValue(forKey: "winver") } else { g["winver"] = v }
        data[appid] = g; save()
    }

    /// Selected compatibility profile id (matched Wine+backend bundle). "" / "auto"
    /// = defer to Uncork's recommendation; play.sh's compat_backend reads this.
    func profile(_ appid: String) -> String { (data[appid]?["profile"] as? String) ?? "auto" }
    func setProfile(_ appid: String, _ v: String) {
        var g = data[appid] ?? [:]
        if v.isEmpty || v == "auto" { g.removeValue(forKey: "profile") } else { g["profile"] = v }
        data[appid] = g; save()
    }

    /// Graphics backend for a NON-Steam game ("auto" = Uncork's default, "d3dmetal",
    /// or "dxmt"). Steam games use the profile picker instead; Epic/GOG launches read
    /// this via UNCORK_BACKEND. "auto"/"" is stored as absent.
    func backend(_ id: String) -> String { (data[id]?["backend"] as? String) ?? "auto" }
    func setBackend(_ id: String, _ v: String) {
        var g = data[id] ?? [:]
        if v.isEmpty || v == "auto" { g.removeValue(forKey: "backend") } else { g["backend"] = v }
        data[id] = g; save()
    }

    /// Extra command-line args appended when launching this game (e.g. "-force-d3d11
    /// -windowed"). Merged after the compat DB's launch_args by play.sh.
    func launchArgs(_ appid: String) -> String { (data[appid]?["launch_args"] as? String) ?? "" }
    func setLaunchArgs(_ appid: String, _ v: String) {
        var g = data[appid] ?? [:]
        let t = v.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { g.removeValue(forKey: "launch_args") } else { g["launch_args"] = t }
        data[appid] = g; save()
    }

    /// Per-game DLL overrides: { "d3d11": "n", "xaudio2_9": "b" } (Wine's n/b/d).
    /// play.sh turns these into a WINEDLLOVERRIDES fragment for the game's launch.
    func dllOverrides(_ appid: String) -> [String: String] {
        (data[appid]?["dll_overrides"] as? [String: String]) ?? [:]
    }
    func setDLLOverride(_ appid: String, _ dll: String, _ mode: String) {
        var g = data[appid] ?? [:]
        var o = (g["dll_overrides"] as? [String: String]) ?? [:]
        if mode.isEmpty { o.removeValue(forKey: dll) } else { o[dll] = mode }
        if o.isEmpty { g.removeValue(forKey: "dll_overrides") } else { g["dll_overrides"] = o }
        data[appid] = g; save()
    }

    /// DLL overrides as an editable "d3d11=n;xaudio2_9=b" string (for a text field).
    func dllOverridesString(_ appid: String) -> String {
        dllOverrides(appid).map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";")
    }
    func setDLLOverridesString(_ appid: String, _ s: String) {
        var o: [String: String] = [:]
        for pair in s.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespaces)
            let v = kv[1].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty, !v.isEmpty { o[k] = v }
        }
        var g = data[appid] ?? [:]
        if o.isEmpty { g.removeValue(forKey: "dll_overrides") } else { g["dll_overrides"] = o }
        data[appid] = g; save()
    }
}
