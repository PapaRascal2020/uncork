import Foundation
import AppKit

/// Save-as-Template / Run-Template: export a perfected store setup as a shareable
/// recipe file, and import someone else's to reproduce it. Templates live as JSON
/// in the store-template schema (see StoreTemplate) under <UNCORK_DATA>/templates,
/// so an imported one immediately appears on the Stores page.
enum TemplateService {

    /// Build the template for a store id, overlaying the user's current tweaks
    /// (chosen engine / Windows version / DLL overrides / launch args from
    /// UserOverrides) onto its base recipe: so "Save as Template" captures the
    /// setup exactly as the user perfected it.
    static func currentTemplate(forLauncherID id: String) -> StoreTemplate {
        var t = StoreTemplates.shared.template(id)
            ?? StoreTemplate(id: id, name: id.capitalized)
        let o = UserOverrides.shared
        let engine = o.profile(id)
        if !engine.isEmpty, engine != "auto" { t.recipe.engine = engine }
        let winver = o.winver(id); if !winver.isEmpty { t.recipe.winver = winver }
        let dll = o.dllOverrides(id); if !dll.isEmpty { t.recipe.dllOverrides = dll }
        let args = o.launchArgs(id)
        if !args.isEmpty { t.recipe.launchFlags = args.split(separator: " ").map(String.init) }
        return t
    }

    /// Prompt to save a template to a .json the user can share.
    static func exportWithPanel(_ t: StoreTemplate) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(t.id).uncork-template.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Export \(t.name) as a shareable Uncork template"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: t.toCatalogDict(),
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url)
            ActivityStore.shared.show("Saved template: \(t.name)")
        } catch { ActivityStore.shared.error("Couldn't save template") }
    }

    /// Import a template file: validate, copy into the user templates dir, reload.
    /// Returns the imported template's id on success.
    @discardableResult
    static func importWithPanel() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an Uncork template (.json) to run"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return importTemplate(from: url)
    }

    @discardableResult
    static func importTemplate(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (obj["id"] as? String) ?? (obj["name"] as? String).map(slug)
        else { ActivityStore.shared.error("That file isn't a valid Uncork template"); return nil }

        let dir = StoreTemplates.userDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dest = URL(fileURLWithPath: dir + "/\(slug(id)).json")
        do {
            // Normalize the id so the filename + in-file id match.
            var norm = obj; norm["id"] = slug(id)
            let out = try JSONSerialization.data(withJSONObject: norm, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: dest)
            StoreTemplates.shared.reload()
            ActivityStore.shared.show("Imported template: \((obj["name"] as? String) ?? id)")
            return slug(id)
        } catch { ActivityStore.shared.error("Couldn't import that template"); return nil }
    }

    /// Remove a user/dev-added template (not a shipped one).
    static func removeUserTemplate(id: String) {
        try? FileManager.default.removeItem(atPath: StoreTemplates.userDir + "/\(id).json")
        StoreTemplates.shared.reload()
    }

    private static func slug(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
