import SwiftUI

/// A browsable record of what Uncork does for each tested game: the shipped
/// compatibility database (Steam titles), plus the user's own per-game tweaks.
struct CompatFixesView: View {
    @State private var query = ""

    private var fixes: [CompatFix] { CompatDB.shared.allFixes() }

    /// Games the user has changed themselves (any store), with a one-line summary.
    private var yours: [(id: String, title: String, source: String, summary: String)] {
        let lib = LibraryStore.shared.games
        return UserOverrides.shared.allIDs().compactMap { id -> (String, String, String, String)? in
            let s = UserOverrides.shared.summary(id)
            guard !s.isEmpty else { return nil }
            let g = lib.first { $0.launchID == id }
            return (id, g?.title ?? id, g?.source.rawValue ?? "", s)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func matches(_ hay: String...) -> Bool {
        query.isEmpty || hay.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What Uncork does for each tested game. Steam titles come from the built-in compatibility database; anything you've changed yourself is under Your settings.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Space.gutter).padding(.top, 6)

                let mine = yours.filter { matches($0.title, $0.summary) }
                if !mine.isEmpty {
                    section("Your settings") {
                        ForEach(mine, id: \.id) { yourCard(id: $0.id, title: $0.title, source: $0.source, summary: $0.summary) }
                    }
                }

                let db = fixes.filter { matches($0.title, $0.notes, $0.anticheat, $0.backend) }
                section("Compatibility database (\(db.count))") {
                    if db.isEmpty {
                        Text("No matches.").font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(.horizontal, DS.Space.gutter)
                    } else {
                        ForEach(db) { fixCard($0) }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Compatibility")
        .searchable(text: $query, prompt: "Search games or fixes")
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.4)
                .foregroundStyle(.secondary).padding(.horizontal, DS.Space.gutter)
            VStack(spacing: 10) { content() }.padding(.horizontal, DS.Space.gutter)
        }
    }

    private func chip(_ text: String, _ tint: Color = .secondary) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(Capsule().fill(tint.opacity(0.15))).foregroundStyle(tint)
    }

    private func fixCard(_ f: CompatFix) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(f.title).font(.system(size: 14, weight: .semibold)); Spacer(); GameCompatBadge(compat: f.verdict) }
            HStack(spacing: 6) {
                if !f.backend.isEmpty { chip(f.backend.uppercased(), DS.accent) }
                if !f.winver.isEmpty { chip(f.winver) }
                if !f.anticheat.isEmpty { chip("anti-cheat: \(f.anticheat)", .red) }
                Spacer(minLength: 0)
            }
            if !f.launchArgs.isEmpty {
                Text("Launch: \(f.launchArgs)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            if !f.notes.isEmpty {
                Text(f.notes).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(Color.secondary.opacity(0.08)))
    }

    private func yourCard(id: String, title: String, source: String, summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.system(size: 14, weight: .semibold)); Spacer(); if !source.isEmpty { chip(source) } }
            Text(summary).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile).fill(DS.accent.opacity(0.08)))
    }
}
