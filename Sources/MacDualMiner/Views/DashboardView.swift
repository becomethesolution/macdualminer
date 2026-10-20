import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UpdateService.self) private var updates
    @Environment(UIState.self) private var uiState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let update = updates.available, !uiState.updateDismissed {
                    UpdateBanner(release: update)
                }
                MachineHeader()
                HeroPanel()
                Panel(title: "Devices", systemImage: "cpu") {
                    VStack(spacing: 0) {
                        DeviceRow(device: .cpu)
                        Divider().padding(.vertical, 6)
                        DeviceRow(device: .gpu)
                    }
                }
                PowerEarningsChart()
                    .frame(height: 300)
                HStack(alignment: .top, spacing: 16) {
                    SwitchingBanner()
                    PowerThermalPanel()
                        .frame(maxWidth: 320)
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Header

private struct MachineHeader: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        let hw = coordinator.hardware
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol(for: hw.modelName.isEmpty ? hw.modelIdentifier : hw.modelName))
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(hw.computerName.isEmpty ? hw.chipName : hw.computerName)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                Text(hw.detailLine)
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private func symbol(for model: String) -> String {
        let m = model.lowercased()
        if m.contains("macbook") { return "laptopcomputer" }
        if m.contains("studio") { return "macstudio" }
        if m.contains("mini") { return "macmini" }
        if m.contains("pro") && !m.contains("book") { return "macpro.gen3" }
        if m.contains("imac") { return "desktopcomputer" }
        return "desktopcomputer"
    }
}

// MARK: - Hero: start/stop + profitability

private struct HeroPanel: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        let e = coordinator.earnings
        let mining = coordinator.isMining
        let net = e.net(.day)
        Panel {
            HStack(alignment: .center, spacing: 28) {
                BigStartButton()
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT PROFITABILITY").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.usd(mining ? net : 0))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(mining ? Theme.money(net) : .secondary)
                        Text("/ day").font(.title3).foregroundStyle(.secondary)
                    }
                    Text(mining
                         ? "Gross \(Format.usd(e.gross(.day))) · Electricity −\(Format.usd(e.power(.day))) · ≈ \(Format.usd(e.net(.month))) / month"
                         : "Press Start to mine \(coordinator.activePlan.summary)")
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                    GridRow {
                        KPITile(label: "Power", value: Format.watts(mining ? e.totalWatts : coordinator.system.systemWatts),
                                detail: mining ? coordinator.powerSourceShort : "Mac right now", color: Theme.power)
                        KPITile(label: "Break-even", value: e.breakEvenUSDPerKWh.map { Format.usd($0) + "/kWh" } ?? "—",
                                detail: "You pay \(Format.usd(coordinator.settings.electricityUSDPerKWh))/kWh")
                    }
                    GridRow {
                        KPITile(label: "Shares", value: "\(coordinator.engines.map(\.acceptedShares).reduce(0, +))",
                                detail: "\(coordinator.engines.map(\.rejectedShares).reduce(0, +)) rejected")
                        KPITile(label: "Running for", value: uptime, detail: coordinator.settings.switchingMode == .auto ? "Auto-switching" : "Manual coins")
                    }
                }
                .frame(width: 300)
            }
        }
    }

    private var uptime: String {
        guard coordinator.isMining, let start = coordinator.engines.compactMap({ $0.process.startedAt }).min() else { return "—" }
        return Duration.seconds(Date().timeIntervalSince(start))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Large round Start/Stop control.
private struct BigStartButton: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        let on = coordinator.wantsMining
        Button {
            coordinator.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(on ? AnyShapeStyle(Theme.loss.opacity(0.15))
                             : AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom)))
                Circle().strokeBorder(on ? Theme.loss : Theme.accent.opacity(0.6), lineWidth: 3)
                VStack(spacing: 4) {
                    Image(systemName: on ? "stop.fill" : "play.fill").font(.system(size: 30, weight: .bold))
                    Text(on ? "STOP" : "START").font(.caption.weight(.heavy)).tracking(1)
                }
                .foregroundStyle(on ? Theme.loss : .white)
            }
            .frame(width: 112, height: 112)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(on ? "Stop mining (⇧⌘M)" : "Start mining (⇧⌘M)")
    }
}

// MARK: - Devices

private struct DeviceRow: View {
    @Environment(MiningCoordinator.self) private var coordinator
    let device: Device

    var body: some View {
        @Bindable var store = coordinator.store
        let hw = coordinator.hardware
        let running = coordinator.runningEngine(on: device)
        let planned = coordinator.activePlan.option(on: device)
        let option = running?.job?.option ?? planned
        let enabled = device == .cpu ? $store.settings.cpuEnabled : $store.settings.gpuEnabled
        let hashrate = running.map { $0.hashrate(for: device) > 0 ? $0.hashrate(for: device) : ($0.displayHashrate ?? 0) }
        let watts = running.flatMap { coordinator.allocatedWatts[$0.kind] }

        HStack(alignment: .center, spacing: 16) {
            Image(systemName: device == .cpu ? "cpu" : "square.stack.3d.up.fill")
                .font(.title2)
                .foregroundStyle(enabled.wrappedValue ? Theme.accent : .secondary)
                .frame(width: 44, height: 44)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(device == .cpu ? "CPU · \(hw.chipName)" : "GPU · \(hw.gpuCores.map { "\($0)-core " } ?? "")\(hw.gpuName)")
                    .font(.headline).lineLimit(1)
                Text(device == .cpu ? hw.coreBreakdown : "Metal · \(coordinator.hardware.memoryGB) GB unified memory")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                statusPill(running: running)
            }
            .frame(width: 260, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(option.map { "\($0.coin?.name ?? $0.coinTag) (\($0.coinTag))" } ?? "—").font(.callout.weight(.semibold))
                Text(option.map { "\($0.coin?.algorithm.rawValue ?? "") · \($0.engine.displayName)" } ?? "No coin ready")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 170, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.hashrate(hashrate)).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                Text("\(Format.watts(watts)) · \(running.map { "\($0.acceptedShares)/\($0.rejectedShares) shares" } ?? "—")")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 140, alignment: .trailing)

            PowerLevelControl(device: device, compact: true)
                .frame(minWidth: 160)
            Toggle("", isOn: enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Mine on the \(device.label)")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusPill(running: (any MiningEngine)?) -> some View {
        if let reason = coordinator.blockReasons[device], coordinator.wantsMining || reason.contains("wallet") || reason.contains("installed") {
            StatusPill(text: reason, color: Theme.accent).lineLimit(1).help(reason)
        } else if let running, running.isMining {
            StatusPill(text: running.statusText == "Mining" || running.statusText == "Running" ? "Mining" : running.statusText, color: Theme.profit)
                .lineLimit(1)
        } else if case .failed(let why) = running?.process.state ?? .stopped {
            StatusPill(text: why, color: Theme.loss).lineLimit(1).help(why)
        } else {
            StatusPill(text: "Stopped", color: .secondary)
        }
    }
}

// MARK: - Chart

/// Power draw (amber area, right axis) against gross and net earnings (lines, left axis) over time.
struct PowerEarningsChart: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UIState.self) private var uiState

    var body: some View {
        @Bindable var ui = uiState
        let samples = coordinator.history.samples(lastHours: ui.chartHours)
        let maxUSD = max(0.01, samples.map { max($0.grossPerDay, $0.netPerDay) }.max() ?? 0)
        let minUSD = min(0, samples.map(\.netPerDay).min() ?? 0)
        let maxW = max(1, samples.map(\.watts).max() ?? 0)
        let scale = maxUSD / maxW             // watts → chart units
        let selected = ui.chartSelection.flatMap { date in samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }

        Panel(title: "Power vs Earnings", systemImage: "chart.xyaxis.line",
              trailing: AnyView(
                Picker("", selection: $ui.chartHours) {
                    Text("1 h").tag(1.0)
                    Text("6 h").tag(6.0)
                    Text("24 h").tag(24.0)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160))) {
            if samples.count < 2 {
                ContentUnavailableView("No history yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Start mining – a point is recorded every 30 seconds and kept for 24 hours."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 16) {
                    legend(color: Theme.power, "Power (W, right axis)")
                    legend(color: Theme.gross, "Gross $/day")
                    legend(color: Theme.profit, "Net $/day")
                    Spacer()
                    if let averages = coordinator.history.averages(lastHours: ui.chartHours) {
                        Text("Avg \(Format.watts(averages.watts)) · \(Format.usd(averages.net))/day net")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Chart {
                    ForEach(samples) { s in
                        AreaMark(x: .value("Time", s.date), y: .value("Power", s.watts * scale))
                            .foregroundStyle(LinearGradient(colors: [Theme.power.opacity(0.35), Theme.power.opacity(0.03)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.date), y: .value("USD per day", s.grossPerDay), series: .value("Series", "Gross"))
                            .foregroundStyle(Theme.gross)
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.date), y: .value("USD per day", s.netPerDay), series: .value("Series", "Net"))
                            .foregroundStyle(Theme.profit)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                    }
                    RuleMark(y: .value("Break-even", 0)).foregroundStyle(.secondary.opacity(0.4))
                    if let selected {
                        RuleMark(x: .value("Selected", selected.date))
                            .foregroundStyle(.secondary)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selected.date.formatted(date: .omitted, time: .shortened)).font(.caption.bold())
                                    Text("Power \(Format.watts(selected.watts))")
                                    Text("Gross \(Format.usd(selected.grossPerDay))/day")
                                    Text("Net \(Format.usd(selected.netPerDay))/day").foregroundStyle(Theme.money(selected.netPerDay))
                                }
                                .font(.caption).monospacedDigit()
                                .padding(8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                    }
                }
                .chartYScale(domain: minUSD...(maxUSD * 1.1))
                .chartXSelection(value: $ui.chartSelection)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(Format.usd(v)) }
                        }
                    }
                    AxisMarks(position: .trailing, values: wattTicks(maxW).map { $0 * scale }) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int((v / scale).rounded())) W") }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
            }
        }
    }

    private func legend(color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 4)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 4–5 round watt values up to the maximum.
    private func wattTicks(_ maxW: Double) -> [Double] {
        let step = [5.0, 10, 20, 25, 50, 100].first { maxW / $0 <= 5 } ?? 100
        return stride(from: 0, through: maxW, by: step).map { $0 }
    }
}

// MARK: - Side panels

private struct PowerThermalPanel: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        let sys = coordinator.system
        Panel(title: "Power & Thermals", systemImage: "bolt.fill") {
            StatRow(label: "Mac power now", value: sys.systemWatts == nil ? "Sensor unavailable" : Format.watts(sys.systemWatts))
            StatRow(label: "Idle baseline", value: sys.idleBaselineWatts == nil ? "Learning…" : Format.watts(sys.idleBaselineWatts))
            StatRow(label: "Thermal pressure", value: sys.thermalLabel)
            StatRow(label: "Power source", value: sys.onBattery ? "Battery" : "AC power")
            StatRow(label: "Idle for", value: Duration.seconds(sys.idleSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
            if let problem = coordinator.profit.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.accent)
            }
        }
    }
}

private struct UpdateBanner: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UpdateService.self) private var updates
    @Environment(UIState.self) private var uiState
    let release: ReleaseInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacDualMiner \(release.version) is available").font(.headline)
                Text(updateDetail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Release notes") { updates.openReleasePage() }
            Button("Install & Restart") {
                Task { await updates.installUpdate { coordinator.shutdown() } }
            }
            .buttonStyle(.borderedProminent)
            .disabled({ if case .downloading = updates.state { return true } else { return false } }())
            Button { uiState.updateDismissed = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private var updateDetail: String {
        switch updates.state {
        case .downloading(let what): return what
        case .failed(let why): return why
        default: return "You have \(updates.currentVersion). Mining stops briefly while the app restarts."
        }
    }
}

/// Shows the switching mode, what's running and any better plan the profit check found.
struct SwitchingBanner: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        let mode = coordinator.settings.switchingMode
        Panel(title: modeTitle(mode), systemImage: mode == .auto ? "arrow.triangle.2.circlepath" : (mode == .recommend ? "lightbulb" : "hand.raised")) {
            Text("Now: \(coordinator.activePlan.summary)").font(.callout)
            if let better = coordinator.recommendedPlan {
                HStack {
                    Text("Better: \(better.summary) – \(Format.usd(better.netUSDPerDay))/day")
                        .font(.callout.weight(.semibold)).foregroundStyle(Theme.profit)
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
            if let status = coordinator.benchmarkStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(coordinator.switchLog.prefix(3), id: \.self) { line in
                Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func modeTitle(_ mode: SwitchingMode) -> String {
        switch mode {
        case .auto: return "Auto-switching"
        case .recommend: return "Recommending"
        case .manual: return "Manual coins"
        }
    }
}
