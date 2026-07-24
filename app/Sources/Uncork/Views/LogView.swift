import SwiftUI
import AppKit

/// Shows a game's launch log (what the scripts and the game itself wrote on the
/// last launch), so a failed or misbehaving game can be diagnosed. Read-only, with
/// copy / reveal-in-Finder / refresh.
struct LogView: View {
    let game: InstalledGame
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(DS.accent)
                Text("\(game.title): launch log").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                Button { revealInFinder() } label: { Image(systemName: "folder") }
                    .help("Reveal the log file in Finder").disabled(!GameLog.exists(game))
                Button { copy() } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy the log").disabled(text.isEmpty)
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(14)
            Divider()

            if text.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("No log yet").font(.system(size: 14, weight: .medium))
                    Text("Launch \(game.title) once, then open this to see what happened.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
        }
        .frame(width: 720, height: 460)
        .onAppear { if !loaded { load(); loaded = true } }
    }

    private func load() { text = GameLog.read(game) ?? "" }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ActivityStore.shared.show("Log copied")
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: GameLog.path(for: game))])
    }
}
