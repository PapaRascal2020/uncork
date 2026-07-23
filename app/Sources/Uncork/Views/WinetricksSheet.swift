import SwiftUI

/// The "protontricks" panel: install Wine components (winetricks verbs) into a
/// SPECIFIC game's bottle. This is how per-game Wine setups happen: an isolated
/// game gets its own components; shared-bottle games note that clearly.
struct WinetricksSheet: View {
    let game: InstalledGame
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ci = ComponentInstaller.shared
    @State private var installed: Set<String> = []
    @State private var custom = ""

    // Route to the game's own store bottle: Steam→"steam", Epic→"epic", custom→its
    // own, so one store's components never land in another store's bottle.
    private var bottle: String { game.bottleName }
    // Steam/Epic use a bottle shared with other games in that store; custom games
    // can be isolated in their own bottle.
    private var shared: Bool { game.source != .custom }

    private struct Verb: Identifiable { let id: String; let label: String }
    private let groups: [(String, [Verb])] = [
        (".NET", [Verb(id: "dotnet40", label: ".NET Framework 4.0"),
                  Verb(id: "dotnet48", label: ".NET Framework 4.8"),
                  Verb(id: "dotnetdesktop6", label: ".NET Desktop Runtime 6")]),
        ("Visual C++", [Verb(id: "vcrun2022", label: "Visual C++ 2015-2022"),
                        Verb(id: "vcrun2019", label: "Visual C++ 2015-2019"),
                        Verb(id: "vcrun2015", label: "Visual C++ 2015")]),
        ("DirectX & media", [Verb(id: "d3dcompiler_47", label: "d3dcompiler_47"),
                             Verb(id: "d3dx9", label: "D3DX9"),
                             Verb(id: "quartz", label: "DirectShow (quartz)"),
                             Verb(id: "wmp11", label: "Windows Media Player")]),
        ("Fonts", [Verb(id: "corefonts", label: "Core fonts"),
                   Verb(id: "tahoma", label: "Tahoma")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Components").font(.system(size: 20, weight: .bold))
                    Text("\(game.title) · bottle “\(bottle)”")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            Text(shared
                 ? "Installs into the shared \(game.source.rawValue) bottle, used by all your \(game.source.rawValue) games. (Steam and Epic have separate bottles.)"
                 : "Installs into this game's own bottle, won't affect other games.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.0) { name, verbs in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(name).font(.system(size: 13, weight: .semibold))
                            ForEach(verbs) { v in row(v.id, v.label) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.secondary.opacity(0.08)))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Other winetricks verb").font(.system(size: 13, weight: .semibold))
                        HStack {
                            TextField("e.g. physx, xact, dxvk…", text: $custom).textFieldStyle(.roundedBorder)
                            Button("Install") {
                                let v = custom.trimmingCharacters(in: .whitespaces)
                                if !v.isEmpty { install(v); custom = "" }
                            }
                            .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.secondary.opacity(0.08)))
                }
            }
        }
        .padding(20).frame(width: 460, height: 540)
        .onAppear(perform: loadInstalled)
    }

    @ViewBuilder private func row(_ id: String, _ label: String) -> some View {
        let st = ci.state(bottle, id)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                if installed.contains(id) || st == .done {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                } else if st == .installing {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("Installing…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if st == .failed {
                    Button { install(id) } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold)).padding(.vertical, 4).padding(.horizontal, 10)
                    }.buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(.orange))
                } else {
                    Button { install(id) } label: {
                        Text("Install").font(.system(size: 11, weight: .bold)).padding(.vertical, 4).padding(.horizontal, 12)
                    }.buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(DS.accent.opacity(0.85)))
                }
            }
            if st == .installing {
                // Live status so the install isn't a silent black box.
                Text(ci.progress(bottle, id))
                    .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private func install(_ verb: String) { ci.install(verb: verb, bottle: bottle) }

    private func loadInstalled() {
        if let s = try? String(contentsOfFile: Paths.winetricksLog(bottle), encoding: .utf8) {
            installed = Set(s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        }
    }
}
