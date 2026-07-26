import Foundation

/// Gathers a store's diagnostics (machine info, Steam client bootstrap log, and crash
/// dumps with their assert messages auto-extracted) so they can be read in-app instead
/// of running `strings` on .dmp files in a Terminal. Read-only.
enum StoreDiagnostics {

    /// The bottle name for a store, or nil if it has no Wine bottle to inspect.
    static func bottleName(for storeID: String) -> String? {
        switch storeID {
        case "steam", "epic", "gog", "ubisoft", "origin": return storeID
        default: return nil          // custom / native stores: no standard bottle
        }
    }

    static func hasDiagnostics(for storeID: String) -> Bool { bottleName(for: storeID) != nil }

    /// Build the full diagnostics text for a store.
    static func report(storeID: String, storeName: String) -> String {
        var out = "== \(storeName) diagnostics ==\n\(machineInfo())\n"
        guard let bottle = bottleName(for: storeID) else {
            return out + "\nThis store has no Wine bottle to inspect.\n"
        }
        let bdir = "\(Paths.bottlesDir)/\(bottle)"
        out += "\nBottle: \(bdir)\n"
        guard FileManager.default.fileExists(atPath: bdir + "/drive_c") else {
            return out + "(bottle not set up yet)\n"
        }
        if storeID == "steam" {
            out += steamReport(bottle: bdir)
        } else {
            out += "\nNo client crash log is wired for \(storeName) yet. Per-game launch logs are on each game in the Library.\n"
        }
        return out
    }

    /// Folder to reveal in Finder for a store (its crash-dump / log dir if present).
    static func revealPath(for storeID: String) -> String? {
        guard let bottle = bottleName(for: storeID) else { return nil }
        let bdir = "\(Paths.bottlesDir)/\(bottle)"
        if storeID == "steam" {
            let dumps = "\(bdir)/drive_c/Program Files (x86)/Steam/dumps"
            if FileManager.default.fileExists(atPath: dumps) { return dumps }
        }
        return FileManager.default.fileExists(atPath: bdir) ? bdir : nil
    }

    // MARK: - pieces

    private static func machineInfo() -> String {
        let ramGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let chip = shell("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let profile = ramGB <= 8 ? "low-resource" : "standard"
        return "Machine: \(chip), \(ramGB) GB RAM, \(os)\nSteam client profile: \(profile)"
    }

    private static func steamReport(bottle: String) -> String {
        let steam = "\(bottle)/drive_c/Program Files (x86)/Steam"
        var out = "\n-- Steam bootstrap log (last 40 lines) --\n"
        out += tail(path: "\(steam)/logs/bootstrap_log.txt", lines: 40) ?? "(no bootstrap_log.txt)\n"

        out += "\n-- Recent crash dumps (assert messages) --\n"
        let dir = "\(steam)/dumps"
        let dumps = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasSuffix(".dmp") }
            .sorted()
        let recent = Array(dumps.suffix(6))
        if recent.isEmpty {
            out += "(no crash dumps, good sign)\n"
        } else {
            for d in recent {
                out += "\n[\(d)]\n\(assertLines(inDump: "\(dir)/\(d)"))\n"
            }
        }
        return out
    }

    /// Extract the human-readable assert lines from a Steam minidump via `strings`
    /// (this is the `strings <dmp> | grep -i assert` we used to run by hand).
    private static func assertLines(inDump path: String) -> String {
        guard let s = shell("/usr/bin/strings", ["-a", path]) else { return "(couldn't read dump)" }
        let hits = s.split(separator: "\n").map(String.init).filter { line in
            let l = line.lowercased()
            return l.contains("assert") || l.contains(".cpp:") || l.contains("illegal")
                || l.contains("fatal") || l.contains("out of memory") || l.contains("bad_alloc")
        }
        // de-dupe, cap.
        var seen = Set<String>(); var kept: [String] = []
        for h in hits where !seen.contains(h) { seen.insert(h); kept.append(h); if kept.count >= 8 { break } }
        return kept.isEmpty ? "(no assert text found)" : kept.joined(separator: "\n")
    }

    private static func tail(path: String, lines: Int) -> String? {
        guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let all = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return all.suffix(lines).joined(separator: "\n") + "\n"
    }

    private static func shell(_ launch: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
