import Foundation
import Combine

/// Runs game installs (Epic→legendary, GOG→gogdl) with a real download queue and
/// live progress, so the UI can show %/size, pause/resume/cancel, and a Steam-like
/// global indicator. Only `maxConcurrent` run at once; the rest wait as `.queued`.
/// legendary and gogdl both resume a partial download, so pause = stop the process
/// (keep it in the list) and resume = re-run the same command.
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    /// How many downloads run simultaneously; the rest queue. One at a time
    /// (Steam-style): concurrent installs into the same store bottle/auth collide,
    /// and a single active download is clearer + faster per-title.
    private let maxConcurrent = 1

    enum State: String, Codable { case queued, downloading, paused, done, failed }

    struct Item: Identifiable, Codable {
        let id: String            // launchID (Epic app_name / GOG id)
        let title: String
        var cover: URL? = nil
        var progress: Double = 0  // 0…1
        var speed: Double = 0     // current download speed, MiB/s
        var detail: String = "Queued"
        var state: State = .queued
        // How to (re)start this install: lets us resume/requeue.
        var script: String
        var args: [String]

        var done: Bool   { state == .done }
        var failed: Bool { state == .failed }
    }

    @Published private(set) var items: [String: Item] = [:]
    /// Preserves insertion order for the queue + stable UI ordering.
    @Published private(set) var order: [String] = []
    /// Peak combined speed seen this session (MiB/s): the "max" for the top bar.
    @Published private(set) var peakSpeed: Double = 0
    /// Rolling recent combined-speed samples (MiB/s) for a small graph.
    @Published private(set) var speedSamples: [Double] = []

    /// Combined live download speed across everything currently downloading (MiB/s).
    var combinedSpeed: Double { downloading.map(\.speed).reduce(0, +) }

    private var procs: [String: Process] = [:]
    private var stoppedIntentionally: Set<String> = []   // paused/cancelled, not a failure
    private let cacheURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Uncork", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheURL = base.appendingPathComponent("downloads-history.json")
        // Restore the whole download list across relaunches. An install in flight
        // when the app quit had its process killed, so restore it as paused (the
        // user can resume: legendary/gogdl continue a partial download). Done/
        // failed keep their state; the history sticks.
        if let d = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([Item].self, from: d) {
            for var it in saved {
                it.speed = 0
                if it.state == .downloading || it.state == .queued {
                    it.state = .paused; it.detail = "Paused, resume to continue"
                }
                items[it.id] = it
                order.append(it.id)
            }
        }
    }

    /// Persist the full download list (order + state) so it survives relaunches.
    private func save() {
        let list = order.compactMap { items[$0] }
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: cacheURL) }
    }

    /// Clear the finished (completed/failed) downloads from the list + history.
    func clearFinished() {
        for id in order where items[id]?.state == .done || items[id]?.state == .failed { items[id] = nil }
        order.removeAll { items[$0] == nil }
        save()
    }
    var hasFinished: Bool { all.contains { $0.state == .done || $0.state == .failed } }

    // Ordered views for the UI.
    var all: [Item]       { order.compactMap { items[$0] } }
    var active: [Item]    { all.filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused } }
    var downloading: [Item] { all.filter { $0.state == .downloading } }
    var paused: [Item]      { all.filter { $0.state == .paused } }
    /// Aggregate progress across everything still in flight (for the global bar).
    var aggregateProgress: Double {
        let inFlight = active
        guard !inFlight.isEmpty else { return 0 }
        return inFlight.map(\.progress).reduce(0, +) / Double(inFlight.count)
    }
    func isInstalling(_ app: String) -> Bool { items[app]?.state == .downloading || items[app]?.state == .queued }

    // MARK: - Public API

    /// Queue a game install from whichever store it belongs to.
    func startInstall(_ game: InstalledGame) {
        switch game.source {
        case .epic: enqueue(id: game.launchID, title: game.title, cover: game.artURL,
                            script: "epic.sh", args: ["install", game.launchID, "--yes", "--skip-sdl"])
        case .gog:
            // Prefer the native macOS build when GOG ships one (runs with no Wine);
            // otherwise the Windows build (via Wine). gog.sh launch auto-detects the
            // installed .app and runs it directly.
            var gogArgs = ["download", game.launchID]
            if game.hasMac { gogArgs += ["--platform", "osx"] }
            enqueue(id: game.launchID, title: game.title, cover: game.artURL,
                    script: "gog.sh", args: gogArgs)
        default: break   // Steam installs via its client; custom games aren't downloaded
        }
    }

    /// Back-compat helper (Epic).
    func startEpic(app: String, title: String, cover: URL? = nil) {
        enqueue(id: app, title: title, cover: cover, script: "epic.sh",
                args: ["install", app, "--yes", "--skip-sdl"])
    }

    func pause(_ id: String) {
        guard var it = items[id] else { return }
        stoppedIntentionally.insert(id)
        procs[id]?.terminate(); procs[id] = nil
        it.state = .paused; it.detail = "Paused"; it.speed = 0; items[id] = it
        save(); pump()
    }

    func resume(_ id: String) {
        guard var it = items[id], it.state == .paused || it.state == .failed else { return }
        it.state = .queued; it.detail = "Queued"; items[id] = it
        save(); pump()
    }

    func cancel(_ id: String) {
        stoppedIntentionally.insert(id)
        procs[id]?.terminate(); procs[id] = nil
        items[id] = nil
        order.removeAll { $0 == id }
        stoppedIntentionally.remove(id)
        save()
        ActivityStore.shared.show("Download cancelled")
        pump()
    }

    // MARK: - Queue

    private func enqueue(id: String, title: String, cover: URL?, script: String, args: [String]) {
        if let existing = items[id], existing.state == .downloading || existing.state == .queued { return }
        var it = Item(id: id, title: title, cover: cover, script: script, args: args)
        it.state = .queued; it.detail = "Queued"
        items[id] = it
        if !order.contains(id) { order.append(id) }
        save()
        ActivityStore.shared.show("Queued \(title)…", seconds: 3)
        pump()
    }

    /// Start queued items until `maxConcurrent` are downloading.
    private func pump() {
        var running = downloading.count
        for id in order where running < maxConcurrent {
            guard let it = items[id], it.state == .queued else { continue }
            launch(id); running += 1
        }
    }

    private func launch(_ id: String) {
        guard var it = items[id], procs[id] == nil else { return }
        it.state = .downloading; it.detail = "Starting…"; items[id] = it
        save()
        ActivityStore.shared.show("Installing \(it.title)…", seconds: 3)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/\(it.script)"] + it.args
        p.environment = Paths.scriptEnvironment(["PYTHONUNBUFFERED": "1"])
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.parse(app: id, chunk: chunk)
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                handle.readabilityHandler = nil
                self?.procs[id] = nil
                guard let self else { return }
                if self.stoppedIntentionally.remove(id) != nil { self.pump(); return } // paused/cancelled
                self.finish(app: id, ok: proc.terminationStatus == 0)
                self.pump()
            }
        }
        procs[id] = p
        do { try p.run() } catch { finish(app: id, ok: false); pump() }
    }

    // MARK: - Progress parsing

    private func parse(app: String, chunk: String) {
        var progress: Double?; var detail: String?; var speed: Double?
        for raw in chunk.split(separator: "\n") {
            let line = String(raw)
            // Progress. legendary: "Progress: 45.2%" (percent). gogdl: "Progress:
            // 0.16 123/456" (0-1 fraction). Disambiguate by the trailing char.
            if let r = line.range(of: "Progress: ") {
                let after = line[r.upperBound...]
                let numStr = after.prefix { $0.isNumber || $0 == "." }
                if let v = Double(numStr) {
                    let rest = after.dropFirst(numStr.count)
                    progress = rest.first == "%" ? v / 100 : min(max(v, 0), 1)
                }
            }
            // Speed: both emit "<n> MiB/s"; take the first (network/raw) rate.
            if let r = line.range(of: " MiB/s") {
                let before = line[..<r.lowerBound]
                let num = String(before.reversed().prefix { $0.isNumber || $0 == "." }.reversed())
                if let v = Double(num) { speed = v }
            }
            if line.contains("Downloaded:") {
                detail = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "[DLManager] INFO: ", with: "")
            }
        }
        guard progress != nil || detail != nil || speed != nil else { return }
        DispatchQueue.main.async {
            guard var it = self.items[app], it.state == .downloading else { return }
            if let pr = progress { it.progress = pr }
            if let sp = speed { it.speed = sp }
            it.detail = detail ?? "\(Int(it.progress * 100))%"
            self.items[app] = it
            // Update session peak + rolling samples for the top bar's graph.
            let combined = self.combinedSpeed
            if combined > self.peakSpeed { self.peakSpeed = combined }
            self.speedSamples.append(combined)
            if self.speedSamples.count > 60 { self.speedSamples.removeFirst(self.speedSamples.count - 60) }
        }
    }

    private func finish(app: String, ok: Bool) {
        guard var it = items[app] else { return }
        // A clean exit isn't proof of a real install: gogdl can exit 0 without
        // downloading (e.g. an auth hiccup). For GOG, verify the game's files
        // actually landed (goggame-<id>.info); otherwise treat it as failed so it
        // doesn't falsely show "installed".
        var success = ok
        if ok && it.script == "gog.sh" && !Self.gogInstalled(it.id) { success = false }
        it.state = success ? .done : .failed
        it.progress = success ? 1 : it.progress
        it.detail = success ? "Installed ✓" : "Didn't finish, tap to retry"
        it.speed = 0
        items[app] = it
        save()
        ActivityStore.shared.show(success ? "\(it.title) installed ✓" : "\(it.title) install didn't finish")
    }

    /// True if a GOG game's files are present (gogdl writes goggame-<id>.info).
    private static func gogInstalled(_ id: String) -> Bool {
        let root = Paths.data + "/bottles/gog/drive_c/GOG Games"
        let fm = FileManager.default
        guard let games = try? fm.contentsOfDirectory(atPath: root) else { return false }
        for g in games {
            if let files = try? fm.contentsOfDirectory(atPath: root + "/" + g),
               files.contains("goggame-\(id).info") { return true }
        }
        return false
    }
}
