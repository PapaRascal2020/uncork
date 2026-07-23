import Foundation

/// Reports the status of everything Uncork relies on, so the Setup screen can
/// show what's ready, what's bundled, and how to get anything that isn't.
enum SystemCheck {
    struct Component: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let ready: Bool
        let group: String        // "Required" | "Graphics engine" | "Stores"
        let hint: String         // what to do / reassurance
        let command: String?     // optional shell command the user can copy
        var installKind: String? = nil   // if set + not ready, Setup shows an Install button (wine|dxvk|gptk)
    }

    private static func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private static func rosettaReady() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        p.arguments = ["-x86_64", "/usr/bin/true"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }

    static func all() -> [Component] {
        let eng = Paths.engine
        let data = Paths.data
        // A component counts as present if it is in the bundled payload OR in the
        // writable per-user engine dir (where on-demand installs land).
        func present(_ rel: String) -> Bool { fileExists("\(eng)/\(rel)") || fileExists("\(data)/engine/\(rel)") }
        let wine = present("wine-stable/bin/wine")
        let dxvk = present("dxvk/x64/d3d11.dll")
        let dxmt = present("wine-stable/lib/wine/x86_64-unix/winemetal.so")
        // D3DMetal (Game Porting Toolkit): the primary backend. Downloaded on
        // first store setup into the writable per-user engine dir, not bundled.
        let gptkWineRoot = "\(data)/engine/gptk/Game Porting Toolkit.app/Contents/Resources/wine"
        let gptk = fileExists("\(gptkWineRoot)/bin/wine64")
            && fileExists("\(gptkWineRoot)/lib/external/D3DMetal.framework")
        let steam = fileExists("\(Paths.steamDir)/steam.exe")
        let legendary = present("legendary-venv/bin/legendary")
        let epicIn = legendary && EpicAuth.isLoggedIn()
        let gogReady = GogAuth.isLoggedIn()

        return [
            Component(name: "Rosetta 2", detail: "Runs x86-64 game code on Apple Silicon.",
                      ready: rosettaReady(), group: "Required",
                      hint: rosettaReady() ? "Installed." : "One-time macOS install. Run the command below in Terminal.",
                      command: rosettaReady() ? nil : "softwareupdate --install-rosetta --agree-to-license"),

            Component(name: "D3DMetal (Game Porting Toolkit)", detail: "Apple's DirectX 11/12 → Metal: the primary graphics backend.",
                      ready: gptk, group: "Graphics engine",
                      hint: gptk ? "Installed (downloaded on first store setup)."
                                 : "Not installed. Click Install to download it now.", command: nil, installKind: "gptk"),
            Component(name: "Wine (engine)", detail: "Translates Windows APIs (no emulation).",
                      ready: wine, group: "Graphics engine",
                      hint: wine ? "Installed." : "Not installed. Click Install to download it now.", command: nil, installKind: "wine"),
            Component(name: "DXMT (alternative)", detail: "DirectX 11 → Metal on the bundled Wine 11: a per-game alternative to D3DMetal.",
                      ready: dxmt, group: "Graphics engine",
                      hint: dxmt ? "Installed: selectable per game via Compatibility profiles."
                                 : "Not installed. Click Install (ships with the Wine engine).", command: nil, installKind: "wine"),
            Component(name: "DXVK (older DirectX)", detail: "DirectX 9/10/11 → Vulkan → Metal, for older titles.",
                      ready: dxvk, group: "Graphics engine",
                      hint: dxvk ? "Installed. Limited on Apple Silicon: MoltenVK lacks the geometry shaders DXVK needs."
                                 : "Not installed. Click Install to download it now.", command: nil, installKind: "dxvk"),

            Component(name: "Steam", detail: "Installed into a bottle; runs hidden in the background.",
                      ready: steam, group: "Stores",
                      hint: steam ? "Installed. Sign in once (Stores → Steam)." : "Install from the Stores tab.", command: nil),
            Component(name: "Epic (legendary)", detail: "Lightweight Epic client, no Epic launcher needed.",
                      ready: epicIn, group: "Stores",
                      hint: !legendary ? "Bundled: connect via Stores → Epic."
                            : epicIn ? "Signed in." : "Sign in via Stores → Epic.", command: nil),
            Component(name: "GOG (gogdl)", detail: "DRM-free GOG library, no GOG Galaxy needed.",
                      ready: gogReady, group: "Stores",
                      hint: gogReady ? "Signed in." : "Connect via Stores → GOG.", command: nil),
        ]
    }
}
