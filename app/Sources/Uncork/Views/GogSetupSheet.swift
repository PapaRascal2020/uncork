import SwiftUI

/// GOG: in-app sign-in via gogdl's browser-code flow (mirrors the Epic sheet).
/// GOG is DRM-free and driven by gogdl: no client GUI. This sheet handles the
/// one-time sign-in; browsing/installing the owned library is a follow-up.
struct GogSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var loggedIn = GogAuth.isLoggedIn()
    @State private var code = ""
    @State private var authorizing = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "g.square.fill").font(.system(size: 22)).foregroundStyle(DS.accent)
                Text("GOG").font(.system(size: 20, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }

            if loggedIn {
                Label("Signed in", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
                Text("GOG is connected. Your DRM-free games install into the GOG bottle and launch on D3DMetal.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
            } else {
                Text("Sign in once, no GOG app needed. Uncork connects directly to your GOG account.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                step(1, "Open the GOG sign-in page and log in.")
                Button { GogAuth.openLogin(); ActivityStore.shared.show("Opened GOG sign-in in your browser") } label: {
                    Label("Open GOG sign-in", systemImage: "safari").font(.system(size: 13, weight: .semibold))
                }
                step(2, "After logging in you'll land on a blank page; that's normal. Its address bar ends with “…?code=XXXX”. Copy that code and paste it here:")
                HStack {
                    TextField("Paste GOG code", text: $code).textFieldStyle(.roundedBorder)
                    Button { authorize() } label: { Text("Connect").font(.system(size: 13, weight: .semibold)) }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || authorizing)
                }
                if authorizing {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Connecting…").font(.system(size: 12)) }
                }
                if failed {
                    Text("That code didn't work; grab a fresh one from the sign-in page and try again.")
                        .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .padding(22).frame(width: 500, height: 380)
    }

    private func authorize() {
        let entered = code
        authorizing = true; failed = false
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = GogAuth.authorize(code: entered)
            DispatchQueue.main.async {
                authorizing = false; loggedIn = ok; failed = !ok
                if ok { ActivityStore.shared.show("GOG connected"); StoreRegistry.shared.markInstalled("gog") }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(DS.accent))
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
