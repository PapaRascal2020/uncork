import Foundation
import Combine

/// Verify-and-repair an installed Epic or GOG game: re-checks the files and
/// re-downloads anything missing or corrupt, via `legendary repair` / `gogdl
/// repair` (both re-run the installer in repair mode). Steam is left to the Steam
/// client's own "Verify integrity of game files".
final class RepairService: ObservableObject {
    static let shared = RepairService()

    enum State: Equatable { case idle, running, done, failed }
    @Published private(set) var states: [String: State] = [:]
    private var procs: [String: Process] = [:]

    static func supported(_ g: InstalledGame) -> Bool {
        (g.source == .epic || g.source == .gog) && g.installed
    }
    func state(for id: String) -> State { states[id] ?? .idle }

    func repair(_ game: InstalledGame) {
        guard Self.supported(game) else { return }
        let id = game.id
        guard states[id] != .running else { return }

        let script: String
        switch game.source {
        case .epic: script = "epic.sh"
        case .gog:  script = "gog.sh"
        default: return
        }

        states[id] = .running
        ActivityStore.shared.show("Verifying & repairing \(game.title)… (this can take a while)", seconds: 10)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/\(script)", "repair", game.launchID]
        p.environment = Paths.scriptEnvironment([:])
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        // Drain the pipe: a repair re-downloads files and is chatty, so an
        // undrained pipe would fill and block the process.
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { _ = $0.availableData }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                handle.readabilityHandler = nil
                self.procs[id] = nil
                if proc.terminationStatus == 0 {
                    self.states[id] = .done
                    ActivityStore.shared.show("\(game.title): verify & repair complete")
                    LibraryStore.shared.refresh()
                } else {
                    self.states[id] = .failed
                    ActivityStore.shared.error("\(game.title): verify & repair failed")
                }
            }
        }
        procs[id] = p
        do { try p.run() } catch {
            states[id] = .failed; procs[id] = nil
            ActivityStore.shared.error("Couldn't start repair")
        }
    }
}
