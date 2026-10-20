import SwiftUI

struct MainWindow: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @State private var tab: Tab = .dashboard

    enum Tab: Hashable { case dashboard, profit, earnings, logs }

    var body: some View {
        TabView(selection: $tab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(Tab.dashboard)
            ProfitCheckView()
                .tabItem { Label("Profit Check", systemImage: "chart.bar.xaxis") }
                .tag(Tab.profit)
            EarningsView()
                .tabItem { Label("Earnings", systemImage: "dollarsign.circle") }
                .tag(Tab.earnings)
            LogsView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
                .tag(Tab.logs)
        }
        .padding(.top, 4)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                StartStopButton()
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
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
        .tint(coordinator.wantsMining ? .red : .green)
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
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
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
