import SwiftUI

struct DashboardView: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                SwitchingBanner()
                HStack(alignment: .top, spacing: 14) {
                    deviceCard(.cpu)
                    deviceCard(.gpu)
                }
                HStack(alignment: .top, spacing: 14) {
                    systemCard
                    earningsSummaryCard
                }
            }
            .padding(18)
        }
    }

    private var header: some View {
        let hw = coordinator.hardware
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hw.chipName).font(.title2.bold())
                Text("\(hw.totalCores) CPU cores (\(hw.superCores) + \(hw.performanceCores)) · \(hw.gpuName) · \(hw.memoryGB) GB")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                StatusDot(color: coordinator.isMining ? .green : (coordinator.wantsMining ? .orange : .secondary))
                Text(coordinator.isBenchmarking ? "Benchmarking" : (coordinator.isMining ? "Mining" : (coordinator.wantsMining ? "Waiting" : "Stopped")))
                    .font(.headline)
            }
        }
    }

    private func deviceCard(_ device: Device) -> some View {
        let running = coordinator.runningEngine(on: device)
        let planned = coordinator.activePlan.option(on: device)
        let coin = (running?.job?.option ?? planned)?.coin
        let title = device == .cpu ? "CPU" : "GPU"
        return Card(title: "\(title) · \(coin.map { "\($0.name) (\($0.tag))" } ?? "idle")",
                    systemImage: device == .cpu ? "cpu" : "square.stack.3d.up") {
            Text(Format.hashrate(running.map { $0.hashrate(for: device) > 0 ? $0.hashrate(for: device) : ($0.displayHashrate ?? 0) }))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            StatRow(label: "Engine", value: (running?.kind ?? planned?.engine).map { "\($0.displayName) · \($0.backend)" } ?? "—")
            StatRow(label: "Algorithm", value: coin?.algorithm.rawValue ?? "—")
            if let running, running.kind.devices.count == 2 {
                StatRow(label: "Shared with", value: device == .cpu ? "GPU (same process)" : "CPU (same process)")
            }
            StatRow(label: "Shares", value: running.map { "\($0.acceptedShares) accepted · \($0.rejectedShares) rejected" } ?? "—")
            StatRow(label: "Pool", value: running?.job?.poolAddress ?? "—")
            StatRow(label: "Status", value: running?.statusText ?? "Stopped")
            PowerLevelControl(device: device, compact: true)
                .font(.callout)
            if let block = coordinator.blockReasons[device], coordinator.wantsMining || block.contains("wallet") || block.contains("installed") {
                HStack(alignment: .top, spacing: 6) {
                    StatusDot(color: .orange).padding(.top, 4)
                    Text(block).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .failed(let why) = running?.process.state ?? .stopped {
                Text(why).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var systemCard: some View {
        let sys = coordinator.system
        let watts = coordinator.allocatedWatts
        let breakdown = watts.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.displayName) \(Format.watts($0.value))" }.joined(separator: ", ")
        return Card(title: "Power & Thermals", systemImage: "bolt.fill") {
            StatRow(label: "Mac power now", value: sys.systemWatts == nil ? "Sensor unavailable" : Format.watts(sys.systemWatts))
            StatRow(label: "Idle baseline", value: sys.idleBaselineWatts == nil ? "Learning…" : Format.watts(sys.idleBaselineWatts))
            StatRow(label: "Charged to mining", value: breakdown.isEmpty ? "—" : breakdown)
            StatRow(label: "Thermal pressure", value: sys.thermalLabel)
            StatRow(label: "Power source", value: sys.onBattery ? "Battery" : "AC power")
            StatRow(label: "Idle for", value: Duration.seconds(sys.idleSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
        }
    }

    private var earningsSummaryCard: some View {
        let e = coordinator.earnings
        return Card(title: "Live Earnings (net of power)", systemImage: "dollarsign.circle") {
            ForEach([Period.hour, .day, .month, .year]) { period in
                StatRow(label: "Per \(period.rawValue.lowercased())", value: Format.usd(e.net(period)))
            }
            if let breakEven = e.breakEvenUSDPerKWh {
                StatRow(label: "Break-even electricity", value: Format.usd(breakEven) + "/kWh")
            }
            if let problem = coordinator.profit.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Text("Details on the Earnings tab").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Shows the switching mode, what's running and any better plan the profit check found.
struct SwitchingBanner: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        let mode = coordinator.settings.switchingMode
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(modeTitle(mode), systemImage: mode == .auto ? "arrow.triangle.2.circlepath" : (mode == .recommend ? "lightbulb" : "hand.raised"))
                    .font(.headline)
                Spacer()
                if let status = coordinator.benchmarkStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text("Now: \(coordinator.activePlan.summary)").font(.callout)
            if let better = coordinator.recommendedPlan {
                HStack {
                    Text("Better: \(better.summary) – \(Format.usd(better.netUSDPerDay))/day")
                        .font(.callout.weight(.semibold)).foregroundStyle(.green)
                    Spacer()
                    Button(mode == .auto ? "Switch now" : "Switch") {
                        coordinator.adopt(better, reason: "Switched to \(better.summary) (from the recommendation)")
                    }
                }
                if mode == .auto {
                    Text("Auto-switch waits until the current coins have run \(coordinator.settings.minimumRunMinutes) min, so DAGs aren't rebuilt constantly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let last = coordinator.switchLog.first {
                Text(last).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func modeTitle(_ mode: SwitchingMode) -> String {
        switch mode {
        case .auto: return "Auto-switching to the most profitable coin"
        case .recommend: return "Recommending the most profitable coin"
        case .manual: return "Manual coin choice"
        }
    }
}
