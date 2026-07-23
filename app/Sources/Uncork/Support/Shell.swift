import Foundation

/// Runs one of Uncork's shell scripts and returns its stdout. stderr is drained
/// on a background thread (both must be read concurrently or a script that fills
/// the 64 KB stderr pipe would deadlock) and, when `report` is set, surfaced to
/// the user on a non-zero exit: so failures are never silent.
enum Shell {
    @discardableResult
    static func run(script: String, _ args: [String], report: String? = nil) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/\(script)"] + args
        p.environment = Paths.scriptEnvironment()
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err

        // Drain stderr concurrently so it can't block the process.
        var errData = Data()
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            errData = err.fileHandleForReading.readDataToEndOfFile(); sem.signal()
        }

        do { try p.run() } catch {
            if let ctx = report { ActivityStore.shared.error("Couldn't \(ctx).") }
            return ""
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        sem.wait()

        if p.terminationStatus != 0, let ctx = report {
            let detail = String(data: errData, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(String.init) ?? "unknown error"
            ActivityStore.shared.error("Couldn't \(ctx): \(detail.prefix(140))")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
