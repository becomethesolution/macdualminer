import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let e = coordinator.earnings
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusDot(color: coordinator.isMining ? .green : (coordinator.wantsMining ? .orange : .secondary))
                Text(coordinator.isMining ? "Mining" : (coordinator.wantsMining ? "Waiting" : "Stopped")).font(.headline)
                Spacer()
                Text(coordinator.hardware.chipName).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ForEach(Device.allCases) { device in
                let running = coordinator.runningEngine(on: device)
                let tag = running?.job?.option.coinTag ?? coordinator.activePlan.option(on: device)?.coinTag ?? "—"
                StatRow(label: "\(device.label) · \(tag)", value: Format.hashrate(running?.hashrate(for: device)))
                if let reason = coordinator.blockReasons[device], coordinator.wants(device) {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            }
            if let better = coordinator.recommendedPlan {
                Button("Switch to \(better.summary)") {
                    coordinator.adopt(better, reason: "Switched to \(better.summary) from the menu bar")
                }
                .font(.caption)
            }
            StatRow(label: "Power", value: Format.watts(e.totalWatts))
            Divider()
            StatRow(label: "Net / hour", value: Format.usd(e.net(.hour)))
            StatRow(label: "Net / day", value: Format.usd(e.net(.day)))
            StatRow(label: "Net / month", value: Format.usd(e.net(.month)))
            Divider()
            HStack {
                StartStopButton()
                    .fixedSize()   // keep "Start All Miners" from truncating
                Spacer()
                Button("Dashboard") {
                    openWindow(id: "dashboard")
                    NSApp.activate()
                }
                SettingsLink { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit (stops mining)")
            }
        }
        .padding(14)
        .frame(width: 340)
        .preferredColorScheme(coordinator.settings.appearance.colorScheme)
        .onAppear { AppAppearance.apply(coordinator.settings.appearance) }
    }
}
