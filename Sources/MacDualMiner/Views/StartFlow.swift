import SwiftUI
import AppKit

/// The "mining at your own risk" notice, shown once before the first Start.
enum Disclaimer {
    /// Bump when the wording changes materially, so everyone sees it once more.
    static let version = 1

    static let title = "Mining at your own risk"
    static let text = """
        MacDualMiner is provided as is, without warranty of any kind. Mining keeps your Mac's CPU and GPU under heavy, sustained load. This raises temperatures, fan use and power consumption, and over time may add wear to your hardware, especially the battery on laptops.

        Earnings are estimates. Coin prices, network difficulty and pool payouts change, and mining can cost more in electricity than it earns.

        You're responsible for your Mac, your electricity costs, and any taxes or local rules that apply to mining.
        """
    static let short = "Provided as is, without warranty. Mining adds heat and wear to your Mac."
}

/// Every Start button goes through here: the one-time notice, then Start, then an explanation if
/// auto mode found nothing worth mining.
@MainActor
enum StartFlow {
    static func toggle(_ coordinator: MiningCoordinator, ui: UIState, openSettings: @escaping () -> Void) {
        if coordinator.wantsMining {
            coordinator.stop()
        } else {
            start(coordinator, ui: ui, openSettings: openSettings)
        }
    }

    static func start(_ coordinator: MiningCoordinator, ui: UIState, openSettings: @escaping () -> Void) {
        guard confirmDisclaimer(coordinator) else { return }
        coordinator.start()
        explainIfNothingProfitable(coordinator, ui: ui, openSettings: openSettings)
    }

    /// "Mine" buttons in Profit Check.
    static func mine(_ option: MiningOption, coordinator: MiningCoordinator) {
        guard confirmDisclaimer(coordinator) else { return }
        coordinator.mine(option)
    }

    /// Shows the notice the first time; returns false if the user cancels.
    static func confirmDisclaimer(_ coordinator: MiningCoordinator) -> Bool {
        guard coordinator.settings.acceptedDisclaimerVersion < Disclaimer.version else { return true }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = Disclaimer.title
        alert.informativeText = Disclaimer.text
        alert.addButton(withTitle: "I Understand – Start Mining")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        coordinator.store.settings.acceptedDisclaimerVersion = Disclaimer.version
        return true
    }

    static func explainIfNothingProfitable(_ coordinator: MiningCoordinator, ui: UIState, openSettings: @escaping () -> Void) {
        guard let report = coordinator.nothingProfitable else { return }
        let s = coordinator.settings
        let least = report.leastCostly
        let device = least.option.engine.deviceLabel
        let alert = NSAlert()
        alert.messageText = "Nothing is profitable right now"
        var info = "At \(Format.usd(s.electricityUSDPerKWh))/kWh, every coin MacDualMiner can mine on this Mac costs more in electricity than it earns. "
        info += "The least costly option is \(least.coinName) on the \(device) at \(Format.usd(least.netUSDPerDay))/day (about \(Format.usd(least.netUSDPerDay * 30.4375))/month)."
        if let setup = report.needsSetup {
            info += "\n\n\(setup.coinName) on the \(setup.option.engine.deviceLabel) would earn about \(Format.usd(setup.netUSDPerDay))/day, but first: \(setup.status.label.lowercased())."
        }
        info += "\n\nKeep Waiting: MacDualMiner checks again every \(s.switchCheckMinutes) minutes and starts mining by itself when a coin becomes profitable."
        alert.informativeText = info
        alert.addButton(withTitle: "Keep Waiting")
        alert.addButton(withTitle: "Mine \(least.option.coinTag) Anyway")
        if report.needsSetup != nil { alert.addButton(withTitle: "Add a Wallet…") }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            coordinator.mineAnyway(least.option)
        case .alertThirdButtonReturn:
            ui.settingsTab = .coins
            openSettings()
        default:
            break
        }
    }
}
