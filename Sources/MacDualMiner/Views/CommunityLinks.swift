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

    /// A new GitHub issue from one of the repo's issue forms, with the app version, Mac and macOS
    /// filled in. Nothing is sent until the user submits the issue on GitHub. The Mac's own name
    /// is left out on purpose.
    @MainActor
    static func feedback(template: String = "bug_report.yml", hardware: HardwareInfo = HardwareInfo.current) -> URL {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        var mac: [String] = []
        let model = hardware.modelName.isEmpty ? hardware.modelIdentifier : hardware.modelName
        if !model.isEmpty { mac.append(model) }
        mac.append(hardware.chipName)
        mac.append("\(hardware.totalCores)-core CPU")
        if let gpu = hardware.gpuCores { mac.append("\(gpu)-core GPU") }
        mac.append("\(hardware.memoryGB) GB")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var parts = URLComponents(string: "https://github.com/becomethesolution/macdualminer/issues/new")!
        parts.queryItems = [
            URLQueryItem(name: "template", value: template),
            URLQueryItem(name: "app-version", value: version),
            URLQueryItem(name: "mac", value: mac.joined(separator: " · ")),
            URLQueryItem(name: "macos", value: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
        ]
        return parts.url ?? issues
    }
}

/// Help menu items and an About panel with a credit line.
struct CommunityCommands: Commands {
    let updates: UpdateService
    let coordinator: MiningCoordinator

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MacDualMiner") { AboutPanel.show() }
        }
        CommandGroup(replacing: .help) {
            Button("MacDualMiner Guide") { CommunityLinks.open(CommunityLinks.guide) }
            Button("\(CommunityLinks.siteName) Community") { CommunityLinks.open(CommunityLinks.community) }
            Divider()
            Button("Check for Updates…") {
                Task { await UpdateCheckAlert.run(updates: updates, coordinator: coordinator) }
            }
            Button("Send Feedback…") { CommunityLinks.open(CommunityLinks.feedback()) }
            Button("Share Your Hashrate…") { CommunityLinks.open(CommunityLinks.feedback(template: "hashrate_report.yml")) }
            Button("View Reported Issues") { CommunityLinks.open(CommunityLinks.issues) }
        }
    }
}

/// "Check for Updates…" from the Help menu: checks GitHub now and reports the result in an alert.
@MainActor
enum UpdateCheckAlert {
    static func run(updates: UpdateService, coordinator: MiningCoordinator) async {
        if case .downloading = updates.state { return }
        await updates.check()
        let alert = NSAlert()
        switch updates.state {
        case .upToDate:
            alert.messageText = "You're up to date"
            alert.informativeText = "MacDualMiner \(updates.currentVersion) is the newest version."
            alert.addButton(withTitle: "OK")
        case .available(let info):
            alert.messageText = "MacDualMiner \(info.version) is available"
            alert.informativeText = "You have \(updates.currentVersion). Install & Restart downloads the update from GitHub, checks it, swaps it in and reopens the app. Mining stops briefly while it restarts."
            alert.addButton(withTitle: "Install & Restart")
            alert.addButton(withTitle: "Release Notes")
            alert.addButton(withTitle: "Later")
        case .failed(let why):
            alert.alertStyle = .warning
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = why + ". Check your internet connection and try again."
            alert.addButton(withTitle: "OK")
        default:
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard case .available = updates.state else { return }
        switch response {
        case .alertFirstButtonReturn:
            await updates.installUpdate { coordinator.shutdown() }
        case .alertSecondButtonReturn:
            updates.openReleasePage()
        default:
            break
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
