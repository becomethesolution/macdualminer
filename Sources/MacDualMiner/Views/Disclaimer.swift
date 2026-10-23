import SwiftUI

/// The "mining at your own risk" notice. Shown as a banner on the Dashboard until dismissed –
/// it never blocks starting.
enum Disclaimer {
    /// Bump when the wording changes materially, so everyone sees it once more.
    static let version = 1

    static let title = "Mining at your own risk"
    static let text = "MacDualMiner is provided as is, without warranty of any kind. Mining keeps your Mac's CPU and GPU under heavy, sustained load. This raises temperatures, fan use and power consumption, and over time may add wear to your hardware, especially the battery on laptops. Earnings are estimates: coin prices, network difficulty and pool payouts change, and mining can cost more in electricity than it earns. You're responsible for your Mac, your electricity costs, and any taxes or local rules that apply to mining."
    static let short = "Provided as is, without warranty. Mining adds heat and wear to your Mac."
}

struct DisclaimerBanner: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(Disclaimer.title).font(.headline)
                Text(Disclaimer.text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Got it") { coordinator.store.settings.acceptedDisclaimerVersion = Disclaimer.version }
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}
