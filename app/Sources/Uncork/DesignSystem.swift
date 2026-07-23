import SwiftUI

/// Shared visual language. App Store-inspired: generous spacing, soft cards,
/// a single warm accent (wine red, on-brand).
enum DS {
    static let accent = Color(red: 0.72, green: 0.16, blue: 0.24)

    enum Radius { static let card: CGFloat = 16; static let tile: CGFloat = 12; static let pill: CGFloat = 100 }
    enum Space  { static let shelf: CGFloat = 28; static let gutter: CGFloat = 20 }
}

/// A capsule action button ("Play" / "Get"), App Store style.
struct ActionPill: View {
    let title: String
    var filled: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.5)
                .frame(minWidth: 64)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(filled ? Color.white : DS.accent)
        .background(
            Capsule().fill(filled ? DS.accent : Color.secondary.opacity(0.15))
        )
    }
}
