import Foundation
import Combine

/// Single source of truth for which game stores are set up. The Stores page and
/// the sidebar bind to this so they show only installed stores: uninstalled ones
/// live behind the "Add a Store" wizard.
///
/// A store counts as installed if the user added it via the wizard (persisted to
/// stores.json) OR its artifacts are already present on disk, so an existing
/// setup is recognised without needing a marker.
final class StoreRegistry: ObservableObject {
    static let shared = StoreRegistry()

    @Published private(set) var installedIDs: Set<String> = []

    private let file: String
    private let fm = FileManager.default

    private init() {
        file = Paths.data + "/stores.json"
        installedIDs = loadPersisted()
        refresh()
    }

    /// Installed stores, in the canonical Launchers order.
    var installed: [Launcher] { Launchers.all.filter { installedIDs.contains($0.id) } }
    /// Stores the user can still add (everything not yet installed).
    var available: [Launcher] { Launchers.all.filter { !installedIDs.contains($0.id) } }

    func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }

    /// Re-detect from on-disk artifacts and merge with the persisted set.
    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            var ids = self.loadPersisted()
            if self.fm.fileExists(atPath: Paths.steamDir + "/steam.exe") { ids.insert("steam") }
            if EpicAuth.isLoggedIn() { ids.insert("epic") }
            if GogAuth.isLoggedIn() { ids.insert("gog") }
            // Ubisoft/EA/Origin are not built-in templates (see Launchers.setupableIDs);
            // they can be added via the Custom Store flow instead.
            // Generic templates (Battle.net, developer-added, imported): installed
            // when their detect_path exists in their "template-<id>" bottle.
            for t in StoreTemplates.shared.all where t.kind == .generic && !t.detectPath.isEmpty {
                // Native (mac) templates install to apps/<id>/ (installed = any .app
                // present, since the bundle name can vary); Windows ones into their
                // template-<id> bottle at detect_path.
                if t.isMac {
                    let dir = Paths.data + "/apps/\(t.id)"
                    let hasApp = ((try? self.fm.contentsOfDirectory(atPath: dir)) ?? []).contains { $0.hasSuffix(".app") }
                    if hasApp { ids.insert(t.id) }
                } else if self.fm.fileExists(atPath: Paths.data + "/bottles/template-\(t.id)/drive_c/" + t.detectPath) {
                    ids.insert(t.id)
                }
            }
            DispatchQueue.main.async { if ids != self.installedIDs { self.installedIDs = ids } }
        }
    }

    /// Mark a store installed: called when an Add-a-Store flow completes.
    func markInstalled(_ id: String) {
        guard !installedIDs.contains(id) else { return }
        installedIDs.insert(id); persist()
    }

    /// Forget a store in the registry (persisted set only).
    func remove(_ id: String) {
        guard installedIDs.contains(id) else { return }
        installedIDs.remove(id); persist()
    }

    /// Fully remove a store: delete the right artifact for its kind, forget it, and
    /// (for user/dev templates) drop its definition so it does not reappear on the
    /// next refresh. Built-in stores (steam/epic/gog) live in a bottle named <id>;
    /// generic Windows templates in "template-<id>"; native (mac) templates in
    /// apps/<id>/.
    func uninstall(_ id: String) {
        ActivityStore.shared.show("Removing \(id.capitalized)…")
        let tmpl = StoreTemplates.shared.template(id)
        let done = { [weak self] in
            if tmpl?.kind == .generic { TemplateService.removeUserTemplate(id: id) }
            self?.remove(id)
            self?.refresh()
            ActivityStore.shared.show("\(id.capitalized) removed. Set it up again anytime")
        }

        // Native (mac) generic template: no bottle, just delete its app dir.
        if let t = tmpl, t.kind == .generic, t.isMac {
            try? fm.removeItem(atPath: Paths.data + "/apps/\(id)")
            DispatchQueue.main.async { done() }
            return
        }

        // Windows: generic templates use "template-<id>" bottles; built-ins use <id>.
        let bottle = (tmpl?.kind == .generic) ? "template-\(id)" : id
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(Paths.scripts)/remove-store.sh", bottle]
        p.environment = Paths.scriptEnvironment(["BOTTLE_NAME": bottle])
        p.standardOutput = Pipe(); p.standardError = Pipe()
        p.terminationHandler = { _ in DispatchQueue.main.async { done() } }
        do { try p.run() } catch { DispatchQueue.main.async { done() } }
    }

    private func loadPersisted() -> Set<String> {
        guard let data = fm.contents(atPath: file),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(arr)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(installedIDs)) {
            try? data.write(to: URL(fileURLWithPath: file))
        }
    }
}
