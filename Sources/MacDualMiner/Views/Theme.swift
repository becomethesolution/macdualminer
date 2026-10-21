import SwiftUI
import AppKit

/// Visual language: charcoal (dark) or soft grey (light) surfaces, a warm amber accent for "mining",
/// green/red for money. Text colours are a shade deeper in light mode so they stay readable on white.
enum Theme {
    static let accent = adaptive(dark: (0.98, 0.64, 0.16), light: (0.90, 0.50, 0.04))      // amber
    static let accentDeep = Color(red: 0.93, green: 0.42, blue: 0.10)
    static let profit = adaptive(dark: (0.25, 0.82, 0.48), light: (0.10, 0.62, 0.32))
    static let loss = adaptive(dark: (0.95, 0.33, 0.33), light: (0.85, 0.20, 0.20))
    static let power = adaptive(dark: (0.98, 0.64, 0.16), light: (0.90, 0.50, 0.04))
    static let gross = adaptive(dark: (0.36, 0.62, 0.98), light: (0.16, 0.44, 0.90))

    /// Window background behind the panels: system default in dark, a soft grey in light so white panels stand out.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? .windowBackgroundColor : NSColor(white: 0.945, alpha: 1)
    })
    /// Panel hairline border.
    static let panelBorder = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.08)
    })

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func adaptive(dark: (Double, Double, Double), light: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = isDark(appearance) ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    static let corner: CGFloat = 14

    static func money(_ value: Double) -> Color { value >= 0 ? profit : loss }
}

/// Rounded panel used throughout the redesigned UI.
struct Panel<Content: View>: View {
    var title: String? = nil
    var systemImage: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

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
        .background(scheme == .dark ? AnyShapeStyle(BackgroundStyle().secondary) : AnyShapeStyle(Color.white),
                    in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 3, y: 1)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.panelBorder))
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
