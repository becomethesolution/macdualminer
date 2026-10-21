import SwiftUI
import AppKit

/// Links to the MacDualMiner guide and the CryptoMiningOnMacs.com community.
/// Site links carry UTM tags so the site's analytics can tell visits that came from the app.
enum CommunityLinks {
    static let siteName = "CryptoMiningOnMacs.com"
    static let tagline = "the macOS crypto mining community"

    static let guide = tagged("https://cryptominingonmacs.com/viewtopic.php?t=170", content: "guide")
    static let community = tagged("https://cryptominingonmacs.com/", content: "community")
    static let issues = URL(string: "https://github.com/becomethesolution/macdualminer/issues")!

    /// Adds utm_source/utm_medium/utm_content to a cryptominingonmacs.com URL.
    static func tagged(_ address: String, content: String) -> URL {
        guard var parts = URLComponents(string: address) else { return URL(string: address)! }
        var items = parts.queryItems ?? []
        items += [URLQueryItem(name: "utm_source", value: "macdualminer"),
                  URLQueryItem(name: "utm_medium", value: "app"),
                  URLQueryItem(name: "utm_content", value: content)]
        parts.queryItems = items
        return parts.url ?? URL(string: address)!
    }

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// Help menu items and an About panel with a credit line.
struct CommunityCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MacDualMiner") { AboutPanel.show() }
        }
        CommandGroup(replacing: .help) {
            Button("MacDualMiner Guide") { CommunityLinks.open(CommunityLinks.guide) }
            Button("\(CommunityLinks.siteName) Community") { CommunityLinks.open(CommunityLinks.community) }
            Divider()
            Button("Report an Issue on GitHub") { CommunityLinks.open(CommunityLinks.issues) }
        }
    }
}

@MainActor
enum AboutPanel {
    static func show() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        let credits = NSMutableAttributedString(string: "Guides and community: ", attributes: base)
        var link = base
        link[.link] = CommunityLinks.tagged("https://cryptominingonmacs.com/", content: "about")
        credits.append(NSAttributedString(string: CommunityLinks.siteName, attributes: link))
        credits.append(NSAttributedString(string: "\nSource code: github.com/becomethesolution/macdualminer", attributes: base))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

/// Small "Community" link for the sidebar footer.
struct CommunityFooterLink: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("COMMUNITY").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Link(CommunityLinks.siteName, destination: CommunityLinks.tagged("https://cryptominingonmacs.com/", content: "sidebar"))
                .font(.caption)
                .tint(Theme.accent)
        }
        .help("Guides, hashrate tables and forum – \(CommunityLinks.tagline)")
    }
}
