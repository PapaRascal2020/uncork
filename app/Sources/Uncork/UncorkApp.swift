import SwiftUI
import AppKit

/// A bare SwiftPM executable launches as a background agent by default, so its
/// window never appears/focuses. This delegate promotes it to a normal
/// foreground app and brings it to front.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Clean shutdown of the prewarmed Steam client when Uncork quits. Steam runs
    /// hidden for fast launches, so on quit it gets `steam.exe -shutdown` (a clean
    /// exit; hard-killing leaves dirty state). Termination is held while the window
    /// hides and a small "Closing" HUD shows, then Steam is shut down off the main
    /// thread so the window never freezes, and only then does the app exit.
    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        // Never interrupt a running game; quit immediately and leave Steam alone.
        guard RunStore.shared.states.allSatisfy({ $0.value != .running }) else { return .terminateNow }
        // Nothing to wind down if the prewarmed Steam client isn't actually up.
        guard RunStore.isRunning("Steam/steam.exe") else { return .terminateNow }

        NSApp.windows.forEach { $0.orderOut(nil) }        // clean disappear, not a freeze
        ShutdownHUD.show(title: "Closing Uncork", detail: "Shutting down Steam…")

        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["\(Paths.scripts)/steam.sh", "-shutdown"]
            p.environment = Paths.scriptEnvironment(["BOTTLE_NAME": "steam"])
            p.standardOutput = Pipe(); p.standardError = Pipe()
            if (try? p.run()) != nil { p.waitUntilExit() }
            // Give the client a moment to actually exit (bounded: never hang quit).
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline && RunStore.isRunning("Steam/steam.exe") { usleep(200_000) }
            DispatchQueue.main.async {
                ShutdownHUD.hide()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

/// A tiny floating panel shown during app-quit so shutting Steam down reads as a
/// deliberate "closing" step, not a frozen window. Borderless + non-activating so
/// it doesn't steal focus or fight the teardown.
enum ShutdownHUD {
    private static var panel: NSPanel?

    static func show(title: String, detail: String) {
        guard panel == nil else { return }
        let host = NSHostingView(rootView: HUD(title: title, detail: detail))
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 264, height: 92),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = host
        p.center()
        p.orderFrontRegardless()
        panel = p
    }

    static func hide() { panel?.orderOut(nil); panel = nil }

    private struct HUD: View {
        let title: String
        let detail: String
        var body: some View {
            HStack(spacing: 14) {
                ProgressView().controlSize(.regular)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .frame(width: 264, height: 92, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08)))
        }
    }
}

@main
struct UncorkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
