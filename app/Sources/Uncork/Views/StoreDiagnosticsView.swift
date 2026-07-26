import SwiftUI
import AppKit

/// Shows a store's crash logs + diagnostics (machine info, Steam bootstrap log, and
/// crash-dump assert messages), so failures can be inspected in-app instead of via a
/// Terminal. Read-only, with copy / reveal-in-Finder / refresh.
struct StoreDiagnosticsView: View {
    let storeID: String
    let storeName: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "stethoscope").foregroundStyle(DS.accent)
                Text("\(storeName): diagnostics").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { load() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
                if StoreDiagnostics.revealPath(for: storeID) != nil {
                    Button { reveal() } label: { Image(systemName: "folder") }.help("Reveal logs in Finder")
                }
                Button { copy() } label: { Image(systemName: "doc.on.doc") }.help("Copy").disabled(text.isEmpty)
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(14)
            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(loading && text.isEmpty ? "Gathering diagnostics…" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .frame(width: 760, height: 520)
        .onAppear { load() }
    }

    private func load() {
        loading = true
        let id = storeID, name = storeName
        DispatchQueue.global(qos: .userInitiated).async {
            let r = StoreDiagnostics.report(storeID: id, storeName: name)
            DispatchQueue.main.async { text = r; loading = false }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ActivityStore.shared.show("Diagnostics copied")
    }

    private func reveal() {
        if let p = StoreDiagnostics.revealPath(for: storeID) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        }
    }
}
