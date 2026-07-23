import SwiftUI
import Foundation

/// A reproducible bottle recipe carried by a store template (and by Save-as-Template
/// exports): everything needed to configure a Wine bottle exactly as the author did.
/// All fields optional: engine, Windows version, and flags are set only when needed.
struct StoreRecipe: Codable, Hashable {
    var engine: String = ""              // Wine engine/version id (engines.json / wine-builds.json), "" = default
    var winver: String = ""              // Windows version the bottle reports: win10/win7/… , "" = default
    var winetricks: [String] = []        // verbs installed into the bottle
    var dllOverrides: [String: String] = [:]   // e.g. {"d3d11":"b"}
    var launchFlags: [String] = []       // extra launch args
    var env: [String: String] = [:]      // extra environment

    enum CodingKeys: String, CodingKey {
        case engine, winver, winetricks, env
        case dllOverrides = "dll_overrides"
        case launchFlags = "launch_flags"
    }
    init() {}
    init(from d: [String: Any]) {
        engine = d["engine"] as? String ?? ""
        winver = d["winver"] as? String ?? ""
        winetricks = d["winetricks"] as? [String] ?? []
        dllOverrides = d["dll_overrides"] as? [String: String] ?? [:]
        launchFlags = d["launch_flags"] as? [String] ?? []
        env = d["env"] as? [String: String] ?? [:]
    }
}

/// A storefront definition: built-in template (Steam/Epic/GOG), developer-added
/// template, or a user's custom store / Save-as-Template export. All share this one
/// schema so the store list is data-driven + extensible.
struct StoreTemplate: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case steam, epic, gog, generic }

    var id: String
    var name: String
    var kind: Kind = .generic
    var platform: String = "windows"    // "windows" (via Wine) | "mac" (native)
    var symbol: String = "bag.fill"
    var tagline: String = ""
    var runsVia: String = ""
    var setupNote: String = ""
    var art: [Double] = [0.16, 0.16, 0.20]        // start rgb
    var artEnd: [Double] = [0.05, 0.05, 0.07]     // end rgb
    var auth: Bool = false
    var recipe: StoreRecipe = StoreRecipe()
    // generic install/launch:
    var installerURL: String = ""
    var installerWaitForExe: String = ""   // stall-proof installs: proceed once this exe appears in the bottle
    var launchPath: String = ""            // exe path relative to the bottle's drive_c
    var detectPath: String = ""            // path relative to drive_c that marks it installed

    var isMac: Bool { platform == "mac" }
    var artStartColor: Color { Color(red: art[safe: 0] ?? 0.16, green: art[safe: 1] ?? 0.16, blue: art[safe: 2] ?? 0.20) }
    var artEndColor: Color { Color(red: artEnd[safe: 0] ?? 0.05, green: artEnd[safe: 1] ?? 0.05, blue: artEnd[safe: 2] ?? 0.07) }

    /// Serialize back to the on-disk catalog schema (nested art/recipe/installer),
    /// so a Save-as-Template export re-imports cleanly via StoreTemplates.
    func toCatalogDict() -> [String: Any] {
        var recipeD: [String: Any] = [:]
        if !recipe.engine.isEmpty { recipeD["engine"] = recipe.engine }
        if !recipe.winver.isEmpty { recipeD["winver"] = recipe.winver }
        if !recipe.winetricks.isEmpty { recipeD["winetricks"] = recipe.winetricks }
        if !recipe.dllOverrides.isEmpty { recipeD["dll_overrides"] = recipe.dllOverrides }
        if !recipe.launchFlags.isEmpty { recipeD["launch_flags"] = recipe.launchFlags }
        if !recipe.env.isEmpty { recipeD["env"] = recipe.env }
        var d: [String: Any] = [
            "id": id, "name": name, "kind": kind.rawValue, "platform": platform,
            "symbol": symbol, "tagline": tagline, "runsVia": runsVia, "setupNote": setupNote,
            "auth": auth, "art": ["start": art, "end": artEnd], "recipe": recipeD,
        ]
        if !installerURL.isEmpty {
            var inst: [String: Any] = ["url": installerURL]
            if !installerWaitForExe.isEmpty { inst["wait_for_exe"] = installerWaitForExe }
            d["installer"] = inst
        }
        if !launchPath.isEmpty { d["launch_path"] = launchPath }
        if !detectPath.isEmpty { d["detect_path"] = detectPath }
        return d
    }

    /// As a Launcher for the Stores UI.
    func toLauncher() -> Launcher {
        Launcher(id: id, name: name, tagline: tagline, symbol: symbol,
                 artStart: artStartColor, artEnd: artEndColor,
                 status: .notInstalled, runsVia: runsVia, setupNote: setupNote,
                 platform: platform)
    }
}

private extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

/// Loads store templates from the shipped catalog (compat/store-templates.json) PLUS
/// any developer/user templates dropped in <UNCORK_DATA>/templates/*.json: so new
/// stores appear with no app rebuild, and Save-as-Template writes here.
final class StoreTemplates {
    static let shared = StoreTemplates()
    private(set) var all: [StoreTemplate] = []

    private init() { reload() }

    /// User/dev template drop-in dir (also where Save-as-Template exports land).
    static var userDir: String { Paths.data + "/templates" }

    func reload() {
        var out: [StoreTemplate] = []
        // 1) shipped catalog
        out += parseCatalog(Paths.payload + "/compat/store-templates.json")
        // 2) user/dev drop-ins (override shipped by id)
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: Self.userDir) {
            for f in files where f.hasSuffix(".json") {
                if let t = parseOne(Self.userDir + "/" + f) {
                    out.removeAll { $0.id == t.id }
                    out.append(t)
                }
            }
        }
        all = out.isEmpty ? fallback() : out
    }

    func template(_ id: String) -> StoreTemplate? { all.first { $0.id == id } }

    private func parseCatalog(_ path: String) -> [StoreTemplate] {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let templates = root["templates"] as? [String: [String: Any]] else { return [] }
        let order = ["steam", "epic", "gog"]
        let ids = order.filter { templates[$0] != nil } + templates.keys.filter { !order.contains($0) }.sorted()
        return ids.compactMap { id in templates[id].map { make(id: id, $0) } }
    }

    /// A single standalone template file: either {template fields...} or {"id":..,...}.
    private func parseOne(_ path: String) -> StoreTemplate? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let id = (obj["id"] as? String) ?? (path as NSString).lastPathComponent.replacingOccurrences(of: ".json", with: "")
        return make(id: id, obj)
    }

    private func make(id: String, _ d: [String: Any]) -> StoreTemplate {
        var t = StoreTemplate(id: id, name: (d["name"] as? String) ?? id)
        t.kind = StoreTemplate.Kind(rawValue: (d["kind"] as? String) ?? "generic") ?? .generic
        t.platform = (d["platform"] as? String) ?? "windows"
        t.symbol = (d["symbol"] as? String) ?? "bag.fill"
        t.tagline = (d["tagline"] as? String) ?? ""
        t.runsVia = (d["runsVia"] as? String) ?? ""
        t.setupNote = (d["setupNote"] as? String) ?? ""
        if let a = d["art"] as? [String: Any] {
            t.art = (a["start"] as? [Double]) ?? t.art
            t.artEnd = (a["end"] as? [Double]) ?? t.artEnd
        }
        t.auth = (d["auth"] as? Bool) ?? false
        if let r = d["recipe"] as? [String: Any] { t.recipe = StoreRecipe(from: r) }
        if let inst = d["installer"] as? [String: Any] {
            t.installerURL = (inst["url"] as? String) ?? ""
            t.installerWaitForExe = (inst["wait_for_exe"] as? String) ?? ""
        }
        t.launchPath = (d["launch_path"] as? String) ?? ""
        t.detectPath = (d["detect_path"] as? String) ?? ""
        return t
    }

    /// Hard-coded fallback (Steam/Epic/GOG) if the catalog is missing.
    private func fallback() -> [StoreTemplate] {
        ["steam": "Steam", "epic": "Epic Games", "gog": "GOG"].map { id, name in
            var t = StoreTemplate(id: id, name: name)
            t.kind = StoreTemplate.Kind(rawValue: id) ?? .generic
            t.auth = true
            return t
        }.sorted { $0.id < $1.id }
    }
}
