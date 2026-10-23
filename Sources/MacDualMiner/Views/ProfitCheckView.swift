import SwiftUI

/// Every coin the bundled engines can mine, with its algorithm, the engine and part of the chip it uses,
/// the hashrate this Mac gets on that algorithm, and what it would earn net of fees and electricity.
struct ProfitCheckView: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UIState.self) private var uiState

    var body: some View {
        let ranked = coordinator.ranked
        let rows = uiState.showIneligibleCoins ? ranked : ranked.filter(\.isEligible)
        let best = ProfitPlanner.bestPlan(ranked, skipUnprofitable: coordinator.settings.idleWhenUnprofitable)
        // A plain ScrollView of rows rather than SwiftUI's Table: Table's selection binding fed back into
        // shared state on every update and blanked the whole window in 0.3.0.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary(best: best, ranked: ranked)
                Panel(title: "All coins this Mac can mine", systemImage: "list.bullet.rectangle") {
                    VStack(spacing: 0) {
                        ProfitHeaderRow()
                        Divider()
                        ForEach(rows) { r in
                            ProfitRow(r: r)
                            Divider().opacity(0.5)
                        }
                    }
                }
                footer
            }
            .padding(20)
        }
    }

    private func summary(best: MiningPlan, ranked: [RankedOption]) -> some View {
        // What each chip makes on its part of the plan, and how much the losing ones cost.
        let parts: [(option: MiningOption, net: Double)] = best.options.map { o in
            (o, ranked.first { $0.option == o }?.netUSDPerDay ?? 0)
        }
        let losing = parts.filter { $0.net < 0 }
        let earning = parts.filter { $0.net >= 0 }
        let idleSaves = -losing.reduce(0) { $0 + $1.net }
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Best option right now").font(.caption).foregroundStyle(.secondary)
                Text(best.summary).font(.headline)
                Text("\(Format.usd(best.netUSDPerDay))/day net · \(Format.usd(best.netUSDPerDay * 30.4375))/month")
                    .font(.callout).foregroundStyle(best.netUSDPerDay >= 0 ? Color.green : Color.red)
                if parts.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(parts, id: \.option) { part in
                            Text("\(part.option.engine.deviceLabel) · \(part.option.coinTag) \(Format.usd(part.net))/day")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(part.net >= 0 ? Color.green : Color.red)
                        }
                    }
                }
                if !losing.isEmpty && !earning.isEmpty {
                    // Start still mines every started chip (the user's choice); this just shows the cost.
                    let names = losing.map { $0.option.engine.deviceLabel }.joined(separator: " and ")
                    Text("The \(names) loses \(Format.usd(idleSaves))/day here. Keeping it idle would make this \(Format.usd(best.netUSDPerDay + idleSaves))/day.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Keep a chip idle while every coin on it loses money", isOn: Binding(
                        get: { coordinator.settings.idleWhenUnprofitable },
                        set: { coordinator.store.settings.idleWhenUnprofitable = $0 }))
                        .toggleStyle(.checkbox).font(.caption)
                }
                if let note = coordinator.benchmarkStatus {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Button {
                        Task { await coordinator.profit.refresh() }
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(coordinator.profit.isRefreshing)
                    if coordinator.isBenchmarking {
                        if let kind = coordinator.benchmarkStepEngine {
                            Button { coordinator.skipBenchmarkStepNow() } label: { Label("Skip \(kind.displayName)", systemImage: "forward.end") }
                                .help("Stop benchmarking \(kind.displayName) and go on to the next engine. Its earlier result, if any, is kept.")
                        }
                        Button(role: .cancel) { coordinator.cancelBenchmark() } label: { Label("Cancel benchmark", systemImage: "xmark") }
                    } else {
                        Button { coordinator.runBenchmark() } label: { Label("Benchmark this Mac", systemImage: "speedometer") }
                            .help("Runs each engine for ~2 minutes on its best ready coin and records hashrate and power")
                        Menu {
                            Section("Include in the benchmark") {
                                ForEach(coordinator.benchmarkablePairs, id: \.key) { pair in
                                    Toggle("\(pair.engine.displayName) · \(pair.algorithm.rawValue)", isOn: Binding(
                                        get: { !coordinator.settings.benchmarkExcluded.contains(pair.key) },
                                        set: { include in
                                            var excluded = coordinator.store.settings.benchmarkExcluded.filter { $0 != pair.key }
                                            if !include { excluded.append(pair.key) }
                                            coordinator.store.settings.benchmarkExcluded = excluded
                                        }))
                                }
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Choose which engines Benchmark this Mac runs. Right-click a coin to benchmark just that one.")
                    }
                }
                if let progress = coordinator.benchmarkProgress {
                    ProgressView(value: progress).frame(width: 200)
                }
                Toggle("Show coins that aren't ready", isOn: Binding(get: { uiState.showIneligibleCoins }, set: { if uiState.showIneligibleCoins != $0 { uiState.showIneligibleCoins = $0 } })).toggleStyle(.checkbox).font(.caption)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                if let updated = coordinator.profit.lastUpdated {
                    Text("Network data: WhatToMine, updated \(updated.formatted(date: .omitted, time: .shortened))")
                }
                if let btc = coordinator.profit.btcUSD { Text("BTC \(Format.usd(btc))") }
                Text("Electricity \(Format.usd(coordinator.settings.electricityUSDPerKWh))/kWh")
                Text(coordinator.settings.useDayAverages ? "24h averages" : "Current values")
            }
            if let problem = coordinator.profit.problem { Text(problem).foregroundStyle(.orange) }
            Text(verbatim: "Not mineable with the bundled engines: " + CoinCatalog.unsupported.map { "\($0.tag) (\($0.algorithmName)) – \($0.reason)" }.joined(separator: "; "))
                .fixedSize(horizontal: false, vertical: true)
            Text("Hashrates marked cryptominingonmacs.com are reference results for your chip until this Mac is benchmarked or has mined for 5 minutes. Click one to see the test it comes from.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private enum ProfitColumns {
    static let coin: CGFloat = 150
    static let algorithm: CGFloat = 90
    static let engine: CGFloat = 120
    static let hashrate: CGFloat = 130
    static let mined: CGFloat = 130
    static let net: CGFloat = 170
    static let volume: CGFloat = 90
    static let action: CGFloat = 64
}

private struct ProfitHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            cell("Coin", ProfitColumns.coin)
            cell("Algorithm", ProfitColumns.algorithm)
            cell("Engine", ProfitColumns.engine)
            cell("Your hashrate", ProfitColumns.hashrate)
            cell("Mined / day", ProfitColumns.mined)
            cell("Net / day", ProfitColumns.net, alignment: .trailing)
            cell("24h volume", ProfitColumns.volume, alignment: .trailing)
            Text("STATUS").frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: ProfitColumns.action)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func cell(_ title: String, _ width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(title.uppercased()).frame(width: width, alignment: alignment)
    }
}

private struct ProfitRow: View {
    @Environment(MiningCoordinator.self) private var coordinator
    let r: RankedOption

    var body: some View {
        let running = coordinator.engines.contains { $0.job?.option == r.option && $0.isMining }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(r.option.coinTag).fontWeight(.semibold)
                    if r.experimental {
                        Text("beta").font(.caption2).padding(.horizontal, 4)
                            .background(Theme.accent.opacity(0.2), in: Capsule())
                    }
                }
                Text(r.coinName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: ProfitColumns.coin, alignment: .leading)

            Text(r.algorithm.rawValue).frame(width: ProfitColumns.algorithm, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(r.option.engine.displayName).lineLimit(1)
                Text(r.option.engine.deviceLabel).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: ProfitColumns.engine, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(Format.hashrate(r.estimate.total)).monospacedDigit()
                if r.estimate.source == .reference, let url = r.estimate.sourceURL {
                    Link(r.estimate.source.label, destination: url)
                        .font(.caption).lineLimit(1)
                        .tint(Theme.accent)
                } else if r.estimate.source == .none && r.isEligible && !coordinator.isBenchmarking {
                    Button("Benchmark") { coordinator.benchmarkOnly(r.option) }
                        .buttonStyle(.link).font(.caption)
                        .help("Measure \(r.option.engine.displayName) on this Mac now (about 2 minutes)")
                } else {
                    Text(r.estimate.source.label).font(.caption).lineLimit(1)
                        .foregroundStyle(r.estimate.source == .reference ? Theme.accent : Color.secondary)
                }
            }
            .frame(width: ProfitColumns.hashrate, alignment: .leading)
            .help(r.estimate.note ?? "")

            Text(r.coinsPerDay > 0 ? Format.coins(r.coinsPerDay, ticker: r.option.coinTag) : "—")
                .monospacedDigit().lineLimit(1)
                .frame(width: ProfitColumns.mined, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.usd(r.netUSDPerDay)).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(Theme.money(r.netUSDPerDay))
                Text("\(Format.usd(r.grossUSDPerDay)) − \(Format.usd(r.powerUSDPerDay)) power")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .frame(width: ProfitColumns.net, alignment: .trailing)

            Text(r.volumeBTC.map { String(format: "%.2f BTC", $0) } ?? "—")
                .monospacedDigit()
                .foregroundStyle((r.volumeBTC ?? 0) < coordinator.settings.minimumLiquidityBTC ? Theme.accent : Color.primary)
                .frame(width: ProfitColumns.volume, alignment: .trailing)

            Label(r.status.label, systemImage: r.isEligible ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption).lineLimit(2)
                .foregroundStyle(r.isEligible ? Theme.profit : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if running {
                    Text("Mining").font(.caption.weight(.semibold)).foregroundStyle(Theme.profit)
                } else {
                    Button("Mine") { coordinator.mine(r.option) }
                        .disabled(!r.isEligible)
                }
            }
            .frame(width: ProfitColumns.action)
        }
        .font(.callout)
        .padding(.vertical, 7)
        .opacity(r.isEligible ? 1 : 0.65)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Benchmark \(r.option.engine.displayName) on \(r.option.coinTag)") { coordinator.benchmarkOnly(r.option) }
                .disabled(!r.isEligible || coordinator.isBenchmarking)
        }
    }
}
