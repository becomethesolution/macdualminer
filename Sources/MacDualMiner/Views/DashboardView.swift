import SwiftUI

struct DashboardView: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(alignment: .top, spacing: 14) {
                    cpuCard
                    gpuCard
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
                Text("\(hw.totalCores) CPU cores (\(hw.superCores) super + \(hw.performanceCores) performance) · \(hw.gpuName) · \(hw.memoryGB) GB")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                StatusDot(color: coordinator.isMining ? .green : (coordinator.wantsMining ? .orange : .secondary))
                Text(coordinator.isMining ? "Mining" : (coordinator.wantsMining ? "Waiting" : "Stopped"))
                    .font(.headline)
            }
        }
    }

    private var cpuCard: some View {
        let cpu = coordinator.cpu
        return Card(title: "CPU · Monero (XMRig)", systemImage: "cpu") {
            Text(Format.hashrate(cpu.hashrate10s))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            StatRow(label: "60s / 15m avg", value: "\(Format.hashrate(cpu.hashrate60s)) / \(Format.hashrate(cpu.hashrate15m))")
            StatRow(label: "Threads", value: cpu.threadsInUse.map(String.init) ?? "—")
            StatRow(label: "Shares", value: "\(cpu.acceptedShares) accepted · \(cpu.rejectedShares) rejected")
            StatRow(label: "Pool", value: cpu.poolAddress ?? coordinator.settings.xmrPool)
            StatRow(label: "Ping", value: cpu.poolPing.map { "\($0) ms" } ?? "—")
            engineStatus(state: cpu.process.state, note: cpu.statusNote, block: coordinator.cpuBlockReason)
        }
    }

    private var gpuCard: some View {
        let gpu = coordinator.gpu
        return Card(title: "GPU · Ravencoin (kawpow-metal)", systemImage: "square.stack.3d.up") {
            Text(Format.hashrate(gpu.hashrate))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            StatRow(label: "Smoothed", value: Format.hashrate(gpu.averageHashrate))
            StatRow(label: "Phase", value: gpu.phase)
            StatRow(label: "Shares", value: "\(gpu.acceptedShares) accepted · \(gpu.rejectedShares) rejected")
            StatRow(label: "Pool", value: coordinator.settings.rvnPool)
            StatRow(label: "Block height", value: gpu.blockHeight.map(String.init) ?? "—")
            engineStatus(state: gpu.process.state, note: nil, block: coordinator.gpuBlockReason)
        }
    }

    private var systemCard: some View {
        let sys = coordinator.system
        let watts = coordinator.allocatedWatts
        return Card(title: "Power & Thermals", systemImage: "bolt.fill") {
            StatRow(label: "Mac power now", value: sys.systemWatts == nil ? "Sensor unavailable" : Format.watts(sys.systemWatts))
            StatRow(label: "Idle baseline", value: sys.idleBaselineWatts == nil ? "Learning…" : Format.watts(sys.idleBaselineWatts))
            StatRow(label: "Charged to mining", value: "\(Format.watts(watts.cpu + watts.gpu)) (CPU \(Format.watts(watts.cpu)), GPU \(Format.watts(watts.gpu)))")
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
            if !coordinator.market.problems.isEmpty {
                ForEach(coordinator.market.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Text("Details on the Earnings tab").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func engineStatus(state: MinerProcess.State, note: String?, block: String?) -> some View {
        let (color, text): (Color, String) = {
            if let block, coordinator.wantsMining || block.contains("wallet") || block.contains("Engine") {
                return (.orange, block)
            }
            switch state {
            case .running: return (.green, note ?? "Running")
            case .stopped: return (.secondary, "Stopped")
            case .restarting(let why): return (.orange, "Restarting – \(why)")
            case .failed(let why): return (.red, why)
            }
        }()
        HStack(alignment: .top, spacing: 6) {
            StatusDot(color: color).padding(.top, 4)
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
