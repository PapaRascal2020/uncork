import Foundation
import Combine

/// Where a store's games download. Reads/sets the symlinked install root for Epic
/// and GOG (Steam is managed by the Steam client, so it's not offered here).
final class InstallLocationService: ObservableObject {
    static let shared = InstallLocationService()

    @Published private(set) var busy: Set<String> = []   // store ids currently moving

    static func supports(_ storeID: String) -> Bool { storeID == "epic" || storeID == "gog" }

    private func subfolder(_ store: String) -> String { store == "epic" ? "EpicGames" : "GOG Games" }

    /// The current install folder for a store (following the symlink), or "".
    func current(store: String) -> String {
        let root = Paths.data + "/bottles/\(store)/drive_c/\(subfolder(store))"
        let fm = FileManager.default
        if let dest = try? fm.destinationOfSymbolicLink(atPath: root) { return dest }
        return fm.fileExists(atPath: root) ? root : ""
    }

    /// Point a store's install folder at `path`, moving any existing games there.
    func set(store: String, path: String) {
        guard Self.supports(store), !busy.contains(store) else { return }
        busy.insert(store)
        ActivityStore.shared.show("Setting \(store.capitalized) install location…", seconds: 8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/install-location.sh", "set", store, path]
        p.environment = Paths.scriptEnvironment([:])
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { _ = $0.availableData }   // drain (a move can be chatty)
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                handle.readabilityHandler = nil
                self?.busy.remove(store)
                if proc.terminationStatus == 0 {
                    ActivityStore.shared.show("\(store.capitalized) games now install to \((path as NSString).lastPathComponent)")
                } else {
                    ActivityStore.shared.error("Couldn't set \(store.capitalized) install location")
                }
            }
        }
        do { try p.run() } catch { busy.remove(store); ActivityStore.shared.error("Couldn't start the move") }
    }
}
