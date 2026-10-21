import SwiftUI
import AppKit

struct MainWindow: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UIState.self) private var uiState
    @Environment(UpdateService.self) private var updates

    var body: some View {
        @Bindable var ui = uiState
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch ui.mainTab {
                case .dashboard: DashboardView()
                case .profit: ProfitCheckView()
                case .earnings: EarningsView()
                case .logs: LogsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { StartStopButton() }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(coordinator.settings.appearance.colorScheme)
        .onChange(of: coordinator.settings.appearance) { _, mode in AppAppearance.apply(mode) }
    }
}

private struct Sidebar: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UpdateService.self) private var updates
    @Environment(UIState.self) private var uiState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacDualMiner").font(.headline)
                    StatusPill(text: statusText, color: statusColor)
                }
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)

            List(selection: Binding<MainTab?>(get: { uiState.mainTab }, set: { if let v = $0, v != uiState.mainTab { uiState.mainTab = v } })) {
                row(.dashboard, "Dashboard", "gauge.with.dots.needle.67percent")
                row(.profit, "Profit Check", "chart.bar.xaxis")
                row(.earnings, "Earnings", "dollarsign.circle")
                row(.logs, "Logs", "text.alignleft")
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 8) {
                let net = coordinator.earnings.net(.day)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NET TODAY'S RATE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(Format.usd(net) + " / day").font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(coordinator.isMining ? Theme.money(net) : .secondary)
                }
                if let update = updates.available {
                    Button {
                        Task { await updates.installUpdate { coordinator.shutdown() } }
                    } label: {
                        Label("Update to \(update.version)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                CommunityFooterLink()
                HStack {
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                        .buttonStyle(.borderless)
                    Spacer()
                    Text("v\(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private func row(_ tab: MainTab, _ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).tag(tab)
    }

    private var statusText: String {
        if coordinator.isBenchmarking { return "Benchmarking" }
        if coordinator.isMining { return "Mining" }
        return coordinator.wantsMining ? "Waiting" : "Stopped"
    }

    private var statusColor: Color {
        coordinator.isMining || coordinator.isBenchmarking ? Theme.profit : (coordinator.wantsMining ? Theme.accent : .secondary)
    }
}

struct StartStopButton: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        Button {
            coordinator.toggle()
        } label: {
            Label(coordinator.wantsMining ? "Stop Mining" : "Start Mining",
                  systemImage: coordinator.wantsMining ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(coordinator.wantsMining ? Theme.loss : Theme.profit)
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9)
    }
}

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        Panel(title: title, systemImage: systemImage) { content }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().textSelection(.enabled)
        }
        .font(.callout)
    }
}
