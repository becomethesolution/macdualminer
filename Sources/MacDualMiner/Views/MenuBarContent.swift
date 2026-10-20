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
            StatRow(label: "CPU · XMR", value: Format.hashrate(coordinator.cpu.hashrate10s))
            if let reason = coordinator.cpuBlockReason, coordinator.wantsMining {
                Text(reason).font(.caption).foregroundStyle(.orange)
            }
            StatRow(label: "GPU · RVN", value: Format.hashrate(coordinator.gpu.hashrate))
            if let reason = coordinator.gpuBlockReason, coordinator.wantsMining {
                Text(reason).font(.caption).foregroundStyle(.orange)
            }
            StatRow(label: "Power", value: Format.watts(e.totalWatts))
            Divider()
            StatRow(label: "Net / hour", value: Format.usd(e.net(.hour)))
            StatRow(label: "Net / day", value: Format.usd(e.net(.day)))
            StatRow(label: "Net / month", value: Format.usd(e.net(.month)))
            Divider()
            HStack {
                StartStopButton()
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
        .frame(width: 320)
    }
}
