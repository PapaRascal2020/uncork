import Foundation
import Combine

enum CloudSyncMode: String { case auto, up, down }

/// Syncs a game's saves with its store's cloud. Epic goes through `legendary
/// sync-saves` (which resolves the save path from the game's metadata); GOG through
/// `gogdl save-sync`, which needs the save folder and a last-sync timestamp that
/// CloudSaveStore keeps. Steam saves ride Steam Cloud inside the Steam client, so
/// Uncork does not manage them; custom games have no cloud.
final class CloudSaveService: ObservableObject {
    static let shared = CloudSaveService()

    enum State: Equatable { case idle, syncing, done, failed }

    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var messages: [String: String] = [:]
    private var procs: [String: Process] = [:]

    static func supported(_ g: InstalledGame) -> Bool { g.source == .epic || g.source == .gog }

    func state(for id: String) -> State { states[id] ?? .idle }
    func message(for id: String) -> String? { messages[id] }

    func sync(_ game: InstalledGame, mode: CloudSyncMode) {
        guard Self.supported(game) else { return }
        let id = game.id
        guard states[id] != .syncing else { return }

        let script: String
        var args: [String]
        switch game.source {
        case .epic:
            script = "epic.sh"
            args = ["sync-saves", game.launchID]
            if mode == .up { args.append("--skip-download") }
            if mode == .down { args.append("--skip-upload") }
            let sp = CloudSaveStore.shared.savePath(id)   // optional override; legendary auto-resolves otherwise
            if !sp.isEmpty { args += ["--save-path", sp] }
        case .gog:
            let sp = CloudSaveStore.shared.savePath(id)
            guard !sp.isEmpty else {
                states[id] = .failed
                messages[id] = "Set this game's save folder first."
                return
            }
            let ts = Int(CloudSaveStore.shared.entry(id).lastSync)
            script = "gog.sh"
            args = ["save-sync", game.launchID, sp, String(ts), mode.rawValue]
        default:
            return
        }

        states[id] = .syncing
        messages[id] = mode == .up ? "Uploading saves…" : mode == .down ? "Downloading saves…" : "Syncing saves…"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/\(script)"] + args
        p.environment = Paths.scriptEnvironment([:])
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let handle = pipe.fileHandleForReading
        var tail = ""     // keep the last bit of CLI output for a useful failure message
        handle.readabilityHandler = { fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            tail = String((tail + s).suffix(500))
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                handle.readabilityHandler = nil
                self.procs[id] = nil
                if proc.terminationStatus == 0 {
                    CloudSaveStore.shared.markSynced(id)
                    self.states[id] = .done
                    self.messages[id] = "Saves synced"
                    ActivityStore.shared.show("\(game.title): saves synced")
                } else {
                    self.states[id] = .failed
                    let last = tail.split(whereSeparator: \.isNewline).map(String.init)
                        .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                    self.messages[id] = last.isEmpty ? "Sync failed" : last
                    ActivityStore.shared.error("\(game.title): cloud save sync failed")
                }
            }
        }
        procs[id] = p
        do { try p.run() } catch {
            states[id] = .failed; messages[id] = "Couldn't start sync"; procs[id] = nil
        }
    }
}
