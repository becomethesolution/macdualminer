import SwiftUI

/// Visual language: dark charcoal surfaces, a warm amber accent for "mining", green/red for money.
enum Theme {
    static let accent = Color(red: 0.98, green: 0.64, blue: 0.16)        // amber
    static let accentDeep = Color(red: 0.93, green: 0.42, blue: 0.10)
    static let profit = Color(red: 0.25, green: 0.82, blue: 0.48)
    static let loss = Color(red: 0.95, green: 0.33, blue: 0.33)
    static let power = Color(red: 0.98, green: 0.64, blue: 0.16)
    static let gross = Color(red: 0.36, green: 0.62, blue: 0.98)

    static let corner: CGFloat = 14

    static func money(_ value: Double) -> Color { value >= 0 ? profit : loss }
}

/// Rounded panel used throughout the redesigned UI.
struct Panel<Content: View>: View {
    var title: String? = nil
    var systemImage: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    if let systemImage {
                        Image(systemName: systemImage).foregroundStyle(Theme.accent)
                    }
                    Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// Small status capsule ("Mining", "Paused", …).
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }
}

/// Label + big number tile.
struct KPITile: View {
    let label: String
    let value: String
    var detail: String? = nil
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
