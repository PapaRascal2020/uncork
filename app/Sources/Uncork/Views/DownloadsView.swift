import SwiftUI

/// Live view of installs (from DownloadManager), grouped by state. Each row can be
/// paused/resumed/cancelled; queued installs wait their turn.
struct DownloadsView: View {
    @ObservedObject private var dl = DownloadManager.shared

    private var downloading: [DownloadManager.Item] { dl.all.filter { $0.state == .downloading } }
    private var queued:      [DownloadManager.Item] { dl.all.filter { $0.state == .queued } }
    private var paused:      [DownloadManager.Item] { dl.all.filter { $0.state == .paused } }
    private var completed:   [DownloadManager.Item] { dl.all.filter { $0.state == .done } }
    private var failed:      [DownloadManager.Item] { dl.all.filter { $0.state == .failed } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Always present, Steam-style: shows live stats when downloading,
                // an idle state otherwise.
                DownloadStatsHeader()
                if dl.all.isEmpty {
                    Text("Installs you start from a store or the Library appear here with live progress.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    section("Downloading", "arrow.down.circle.fill", DS.accent, downloading)
                    section("Queued",      "clock.fill",             .secondary, queued)
                    section("Paused",      "pause.circle.fill",      .secondary, paused)
                    section("Completed",   "checkmark.circle.fill",  .green,     completed)
                    section("Failed",      "exclamationmark.triangle.fill", .red, failed)
                }
            }
            .padding(DS.Space.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Downloads")
        .toolbar {
            if dl.hasFinished {
                ToolbarItem {
                    Button { dl.clearFinished() } label: { Label("Clear finished", systemImage: "xmark.bin") }
                        .help("Clear completed & failed downloads")
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ icon: String, _ tint: Color, _ items: [DownloadManager.Item]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text("\(items.count)")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                ForEach(items) { DownloadRow(item: $0) }
            }
        }
    }
}

/// Steam-style stats banner at the top of the Downloads page: current combined
/// speed, session peak ("max"), how many are downloading, aggregate progress, and
/// a small live speed graph.
struct DownloadStatsHeader: View {
    @ObservedObject private var dl = DownloadManager.shared
    private func mbps(_ v: Double) -> String { String(format: "%.1f MB/s", v) }

    var body: some View {
        let count = dl.downloading.count
        let active = count > 0 || !dl.paused.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(active ? mbps(dl.combinedSpeed) : "Idle")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? .primary : .secondary)
                    Text(subtitle(count: count, active: active))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                stat("Peak", dl.peakSpeed > 0 ? mbps(dl.peakSpeed) : "-")
                stat("Progress", active ? "\(Int(dl.aggregateProgress * 100))%" : "-")
            }
            SpeedGraph(samples: dl.speedSamples, peak: dl.peakSpeed).frame(height: 40)
                .opacity(dl.speedSamples.isEmpty ? 0.35 : 1)
            ProgressView(value: active ? dl.aggregateProgress : 0).tint(DS.accent)
                .opacity(active ? 1 : 0.3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.white.opacity(0.06)))
    }

    private func subtitle(count: Int, active: Bool) -> String {
        if count > 0 { return count == 1 ? "downloading 1 game" : "downloading \(count) games" }
        if !dl.paused.isEmpty { return "paused" }
        return "No active downloads"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

/// Lightweight live speed sparkline (bars), scaled to the session peak.
struct SpeedGraph: View {
    let samples: [Double]
    let peak: Double

    var body: some View {
        GeometryReader { geo in
            let shown = Array(samples.suffix(48))
            let maxV = max(peak, shown.max() ?? 0, 0.001)
            let n = max(shown.count, 1)
            let barW = geo.size.width / CGFloat(n)
            HStack(alignment: .bottom, spacing: max(1, barW * 0.15)) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(DS.accent.opacity(0.75))
                        .frame(height: max(2, geo.size.height * CGFloat(v / maxV)))
                }
                if shown.isEmpty { Color.clear }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

struct DownloadRow: View {
    let item: DownloadManager.Item
    private var dl: DownloadManager { .shared }

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: item.cover) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                    Image(systemName: "gamecontroller.fill").foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .frame(width: 84, height: 48).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if item.state == .downloading || item.state == .paused {
                        Text("\(Int(item.progress * 100))%")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                if item.state == .downloading || item.state == .paused {
                    ProgressView(value: item.progress).tint(item.state == .paused ? .secondary : DS.accent)
                }
                Text(item.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }

            controls
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 8) {
            switch item.state {
            case .downloading:
                iconButton("pause.fill", "Pause") { dl.pause(item.id) }
                iconButton("xmark", "Cancel") { dl.cancel(item.id) }
            case .queued:
                iconButton("xmark", "Cancel") { dl.cancel(item.id) }
            case .paused:
                iconButton("play.fill", "Resume") { dl.resume(item.id) }
                iconButton("xmark", "Cancel") { dl.cancel(item.id) }
            case .failed:
                pill("Retry", "arrow.clockwise", .orange) { dl.resume(item.id) }
                iconButton("xmark", "Dismiss") { dl.cancel(item.id) }
            case .done:
                EmptyView()
            }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
    }

    private func pill(_ title: String, _ symbol: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .bold))
                .padding(.vertical, 5).padding(.horizontal, 12)
        }
        .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(color))
    }
}
