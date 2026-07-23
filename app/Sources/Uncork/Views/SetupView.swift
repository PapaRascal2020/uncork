import SwiftUI
import AppKit

/// A guide + status board for everything Uncork depends on: what's ready,
/// what's bundled (nothing to do), and how to get anything that isn't standard.
struct SetupView: View {
    @State private var components = SystemCheck.all()
    @ObservedObject private var installer = SetupInstaller.shared
    private let order = ["Required", "Graphics engine", "Stores"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("What Uncork needs, and what's already handled for you.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)

                ForEach(order, id: \.self) { group in
                    let items = components.filter { $0.group == group }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.uppercased())
                                .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(.secondary)
                            ForEach(items) { row($0) }
                        }
                    }
                }

                // Pointers to the per-game tools + the open-source guide.
                VStack(alignment: .leading, spacing: 8) {
                    Label("Per-game troubleshooting lives on each game's page (Library → a game): pick or download a Compatibility profile (the Mac take on Steam's Proton-version picker) plus Windows version, launch options and performance overlay.",
                          systemImage: "slider.horizontal.3")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Uncork is open source: see the Developer Guide in the sidebar for how it all works.",
                          systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(Color.secondary.opacity(0.06)))
            }
            .padding(28).frame(maxWidth: 740, alignment: .leading)
        }
        .navigationTitle("Setup")
        .toolbar { Button { components = SystemCheck.all() } label: { Image(systemName: "arrow.clockwise") } }
    }

    private func row(_ c: SystemCheck.Component) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: c.ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18)).foregroundStyle(c.ready ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).font(.system(size: 14, weight: .semibold))
                Text(c.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(c.hint).font(.system(size: 12)).foregroundStyle(c.ready ? .secondary : .primary)
                if let cmd = c.command {
                    HStack(spacing: 8) {
                        Text(cmd).font(.system(size: 11, design: .monospaced))
                            .padding(.vertical, 5).padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.14)))
                            .textSelection(.enabled)
                        Button { copy(cmd) } label: { Label("Copy", systemImage: "doc.on.doc").font(.system(size: 11)) }
                            .buttonStyle(.plain).foregroundStyle(DS.accent)
                    }
                    .padding(.top, 3)
                }
                // Install button for a not-ready component that can be fetched on demand.
                if !c.ready, let kind = c.installKind {
                    if installer.installing == kind {
                        HStack(spacing: 8) {
                            ProgressView(value: installer.fraction).frame(width: 130).tint(DS.accent)
                            Text(installer.message.isEmpty ? "Installing…" : installer.message)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.top, 5)
                    } else {
                        Button { installer.install(kind) { components = SystemCheck.all() } } label: {
                            Label("Install", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.vertical, 5).padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .background(Capsule().fill(DS.accent))
                        .disabled(installer.installing != nil)
                        .padding(.top, 5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(Color.secondary.opacity(0.06)))
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        ActivityStore.shared.show("Command copied to clipboard")
    }
}
