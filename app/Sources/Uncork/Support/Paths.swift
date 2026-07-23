import Foundation

/// Resolves where Uncork finds its read-only payload (engine, scripts, tools,
/// compat DB) and where it keeps writable per-user state (bottles, store config).
///
/// Two roots, so the app is relocatable and runs on any Mac:
///   • payload: read-only. Shipped: bundled at Uncork.app/Contents/Resources/uncork
///     (engine/, scripts/, tools/, compat/). Dev (`swift run`, unbundled binary):
///     the project checkout.
///   • data: writable per-user state at ~/Library/Application Support/Uncork
///     (bottles, legendary config, caches). Same location in dev and shipped, so
///     both behave identically and never write into the read-only payload.
enum Paths {
    /// Read-only payload root.
    static let payload: String = {
        // Shipped: the bundled payload sits beside the executable in Resources.
        if let res = Bundle.main.resourcePath {
            let bundled = res + "/uncork"
            if FileManager.default.fileExists(atPath: bundled + "/scripts/lib.sh") {
                return bundled
            }
        }
        // Dev fallback: derive the source checkout root from this file's own
        // compile-time path. Paths.swift lives at
        // app/Sources/Uncork/Support/Paths.swift, five levels below the root.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // Uncork
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // app
            .deletingLastPathComponent()   // repo root
            .path
    }()

    /// Writable per-user data root: ~/Library/Application Support/Uncork.
    static let data: String = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = base?.appendingPathComponent("Uncork").path
            ?? (NSHomeDirectory() + "/Library/Application Support/Uncork")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    // --- Read-only payload locations ----------------------------------------
    static var scripts: String  { payload + "/scripts" }
    static var tools: String    { payload + "/tools" }
    static var engine: String   { payload + "/engine" }
    static var compatDB: String { payload + "/compat/gamefixes.json" }

    // --- Writable state locations -------------------------------------------
    static var bottlesDir: String { data + "/bottles" }
    static func bottleDir(_ name: String) -> String { bottlesDir + "/" + name }
    static func winetricksLog(_ bottle: String) -> String { bottleDir(bottle) + "/winetricks.log" }
    static var legendaryConfig: String { data + "/legendary" }

    static var steamDir: String {
        bottleDir("steam") + "/drive_c/Program Files (x86)/Steam"
    }
    static var steamApps: String { steamDir + "/steamapps" }

    /// Base environment for every spawned script. Points lib.sh / epic.sh at the
    /// read-only payload (engine, tools) and the writable data dir (bottles,
    /// legendary config) instead of their PROJECT_ROOT-relative dev defaults,
    /// which is what makes the shipped, relocated app work. Merge site-specific
    /// values (BOTTLE_NAME, etc.) through `overrides`.
    static func scriptEnvironment(_ overrides: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ENGINE_DIR"]            = engine
        env["BOTTLES_DIR"]           = bottlesDir
        env["WINE_HOME"]             = engine + "/wine-stable"
        env["DXVK_DIR"]              = engine + "/dxvk"
        env["LEGENDARY_CONFIG_PATH"] = legendaryConfig
        env["UNCORK_DATA"]           = data
        env["UNCORK_CACHE"]          = data + "/cache"
        overrides.forEach { env[$0.key] = $0.value }
        return env
    }
}
