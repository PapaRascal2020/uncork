import SwiftUI
import Combine

/// A tiny transient status HUD so actions never feel dead: the moment a button
/// is tapped we show "Starting Steam…" / "Launching X…", auto-dismissing shortly.
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()
    @Published var message: String?
    @Published var isError = false
    private var clear: DispatchWorkItem?

    func show(_ message: String, seconds: Double = 3.0, isError: Bool = false) {
        DispatchQueue.main.async {
            self.message = message
            self.isError = isError
            self.clear?.cancel()
            let w = DispatchWorkItem { [weak self] in withAnimation { self?.message = nil } }
            self.clear = w
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
        }
    }

    /// A failure the user should actually notice: red, and it lingers longer.
    func error(_ message: String) { show(message, seconds: 7.0, isError: true) }
}

/// Bottom-centered pill that shows the current ActivityStore message.
struct ToastView: View {
    @ObservedObject private var activity = ActivityStore.shared

    var body: some View {
        VStack {
            Spacer()
            if let m = activity.message {
                HStack(spacing: 10) {
                    if activity.isError {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(m).font(.system(size: 13, weight: .medium))
                        .lineLimit(2).frame(maxWidth: 420, alignment: .leading)
                }
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(activity.isError ? Color.red.opacity(0.5) : .white.opacity(0.08)))
                .shadow(radius: 12, y: 4)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activity.message)
        .allowsHitTesting(false)
    }
}
