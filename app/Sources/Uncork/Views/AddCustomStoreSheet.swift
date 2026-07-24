import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Add a Custom Store: a storefront that isn't a built-in template. Windows: pick
/// its installer, Uncork installs it into a fresh bottle and finds the client .exe.
/// macOS: pick the native .app (a shortcut). Optionally point at a games folder so
/// Uncork surfaces its titles in the Library. See CustomStoresStore.
struct AddCustomStoreSheet: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var installer = CustomStoreInstaller.shared

    @State private var name = ""
    @State private var platform = "windows"      // "windows" | "mac"
    @State private var filePath = ""             // Windows: installer. Mac: the .app.
    @State private var gamesDir = ""
    @State private var storeURL = ""             // optional web storefront to browse in-app
    @State private var engine = "wine-stable"    // chosen Wine version (Windows only)
    @State private var winver = ""               // OS / Windows version (Windows only)
    @State private var flags = ""                // extra launch flags (Windows only)
    @State private var busy = false
    @State private var error = ""

    // After a Windows install, pick the launcher .exe (auto-detected default).
    enum Phase { case form, chooseLauncher }
    @State private var phase: Phase = .form
    @State private var installedBottle = ""
    @State private var launcherExe = ""       // unix path to the chosen launcher .exe

    private var isMac: Bool { platform == "mac" }

    /// Selectable Wine versions: bundled default + downloaded Wine builds + CEF.
    private var engineOptions: [(String, String)] {
        var opts: [(String, String)] = [("wine-stable", "Default (Wine 11 + DXMT)")]
        opts += WineBuildsCatalog.shared.all.map { ($0.id, "\($0.name) \($0.version)") }
        opts += [("wine-cef", "CrossOver CEF (32-bit clients)")]
        return opts
    }
    private let winverOptions: [(String, String)] = [
        ("", "Default"), ("win11", "Windows 11"), ("win10", "Windows 10"),
        ("win7", "Windows 7"), ("winxp", "Windows XP"),
    ]
    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !filePath.isEmpty && !busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "plus.rectangle.on.folder.fill").foregroundStyle(DS.accent)
                Text("Add a Custom Store").font(.system(size: 20, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            Text("Add any storefront yourself. Uncork installs Windows clients in their own Wine bottle, or runs a native macOS app directly.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if phase == .chooseLauncher {
                chooseLauncherContent
            } else {
            field("Name") { TextField("e.g. Battle.net", text: $name).textFieldStyle(.roundedBorder) }

            field("Platform") {
                Picker("", selection: $platform) {
                    Text("Windows (via Wine)").tag("windows")
                    Text("macOS (native)").tag("mac")
                }.pickerStyle(.segmented).labelsHidden()
            }

            field(isMac ? "App (.app)" : "Installer (.exe / .msi)") {
                HStack {
                    Text(filePath.isEmpty ? "Nothing chosen" : (filePath as NSString).lastPathComponent)
                        .font(.system(size: 12)).foregroundStyle(filePath.isEmpty ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(isMac ? "Choose app…" : "Choose installer…") { pickFile() }
                }
            }

            // Wine configuration: only relevant to Windows stores (Mac is native).
            if !isMac {
                field("Wine version") {
                    Picker("", selection: $engine) {
                        ForEach(engineOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.labelsHidden()
                }
                field("Windows version (OS)") {
                    Picker("", selection: $winver) {
                        ForEach(winverOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.menu).labelsHidden()
                }
                field("Launch flags (optional)") {
                    TextField("e.g. --no-sandbox -windowed", text: $flags)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                }
            }

            field("Games folder (optional)") {
                HStack {
                    Text(gamesDir.isEmpty ? "Not set (no Library scan)" : (gamesDir as NSString).lastPathComponent)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose folder…") { pickGamesDir() }
                    if !gamesDir.isEmpty { Button { gamesDir = "" } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain) }
                }
                Text("If set, Uncork scans it for this store's \(isMac ? ".app" : ".exe") games and shows them in your Library.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            field("Store page (optional)") {
                TextField("e.g. store.epicgames.com", text: $storeURL)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                Text("If this store has a web storefront where you buy or claim games, add it here to browse it inside Uncork (a \"Browse\" entry appears in the sidebar). Leave blank if it has no web store.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if busy {
                ProgressView(value: installer.fraction).progressViewStyle(.linear).tint(DS.accent)
                Text(installer.message.isEmpty ? "Installing…" : installer.message).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Spacer()
                Button(action: add) {
                    Text(isMac ? "Add Store" : "Install & Add").font(.system(size: 13, weight: .bold))
                        .padding(.vertical, 6).padding(.horizontal, 16)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Capsule().fill(DS.accent.opacity(canAdd ? 1 : 0.4)))
                .disabled(!canAdd)
            }
            }  // end phase == .form
        }
        .padding(22).frame(width: 480)
    }

    /// After the Windows installer runs: confirm / pick the store's launcher .exe
    /// (prefilled with the auto-detected best guess; browsable inside the bottle).
    @ViewBuilder private var chooseLauncherContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installed into bottle '\(installedBottle)'", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
            Text("Choose the store's launcher app: the .exe that opens the store. Uncork guessed one; change it if it's wrong.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            field("Launcher .exe") {
                HStack {
                    Text(launcherExe.isEmpty ? "Not chosen" : (launcherExe as NSString).lastPathComponent)
                        .font(.system(size: 12)).foregroundStyle(launcherExe.isEmpty ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose .exe…") { pickLauncherExe() }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    _ = CustomStoresStore.shared.add(name: name, platform: "windows", launchPath: launcherExe,
                                                     bottle: installedBottle, gamesDir: gamesDir,
                                                     engine: engine, winver: winver, launchFlags: flags,
                                                     storeURL: storeURL)
                    finish()
                } label: {
                    Text("Add to Uncork").font(.system(size: 13, weight: .bold)).padding(.vertical, 6).padding(.horizontal, 16)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Capsule().fill(DS.accent.opacity(launcherExe.isEmpty ? 0.4 : 1)))
                .disabled(launcherExe.isEmpty)
            }
        }
    }

    /// Browse for the launcher .exe, rooted at the store's bottle so the user lands
    /// right in its Program Files.
    private func pickLauncherExe() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .item]
        panel.allowsMultipleSelection = false; panel.canChooseFiles = true; panel.canChooseDirectories = false
        let bottleC = Paths.data + "/bottles/\(installedBottle)/drive_c"
        if FileManager.default.fileExists(atPath: bottleC) { panel.directoryURL = URL(fileURLWithPath: bottleC) }
        panel.message = "Choose the store's launcher .exe (inside its bottle)"
        if panel.runModal() == .OK, let url = panel.url { launcherExe = url.path }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if isMac {
            panel.allowedContentTypes = [.application]
            panel.treatsFilePackagesAsDirectories = false
            panel.message = "Choose the store's macOS app (.app)"
        } else {
            panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .item, UTType(filenameExtension: "msi") ?? .item]
            panel.message = "Choose the store's Windows installer (.exe / .msi)"
        }
        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        }
    }

    private func pickGamesDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose the folder where this store installs its games"
        if panel.runModal() == .OK, let url = panel.url { gamesDir = url.path }
    }

    private func add() {
        error = ""
        if isMac {
            // Native app → straight shortcut, no install, no Wine.
            _ = CustomStoresStore.shared.add(name: name, platform: "mac", launchPath: filePath,
                                             bottle: nil, gamesDir: gamesDir, storeURL: storeURL)
            finish()
        } else {
            // Windows → install the client into its own bottle on the CHOSEN Wine
            // version + Windows version, then record the exe + flags.
            busy = true
            let bottle = "custom-store-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
            CustomStoreInstaller.shared.install(bottle: bottle, installerPath: filePath,
                                                engine: engine, winver: winver) { foundExe in
                busy = false
                // Install done: move to the launcher-pick step. Prefill the
                // auto-detected .exe (may be empty → user browses the bottle).
                installedBottle = bottle
                launcherExe = foundExe ?? ""
                phase = .chooseLauncher
            }
        }
    }

    private func finish() {
        ActivityStore.shared.show("\(name) added")
        StoreRegistry.shared.markInstalled("custom-store")   // nudge Stores refresh
        onDone(); dismiss()
    }
}
