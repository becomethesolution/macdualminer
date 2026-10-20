import SwiftUI

/// Every coin the bundled engines can mine, with its algorithm, the engine and part of the chip it uses,
/// the hashrate this Mac gets on that algorithm, and what it would earn net of fees and electricity.
struct ProfitCheckView: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UIState.self) private var uiState

    var body: some View {
        @Bindable var ui = uiState
        let ranked = coordinator.ranked
        let rows = ui.showIneligibleCoins ? ranked : ranked.filter(\.isEligible)
        let best = ProfitPlanner.bestPlan(ranked, skipUnprofitable: false)
        VStack(alignment: .leading, spacing: 12) {
            summary(best: best)
            Table(rows, selection: $ui.profitSelection) {
                TableColumn("Coin") { r in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(r.option.coinTag).fontWeight(.semibold)
                            if r.experimental {
                                Text("beta").font(.caption2).padding(.horizontal, 4)
                                    .background(.orange.opacity(0.2), in: Capsule())
                            }
                        }
                        Text(r.coinName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .width(min: 90, ideal: 120)
                TableColumn("Algorithm") { r in Text(r.algorithm.rawValue) }
                    .width(min: 70, ideal: 80)
                TableColumn("Engine") { r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.option.engine.displayName)
                        Text(r.option.engine.deviceLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .width(min: 90, ideal: 110)
                TableColumn("Your hashrate") { r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Format.hashrate(r.estimate.total)).monospacedDigit()
                        Text(r.estimate.source.label).font(.caption)
                            .foregroundStyle(r.estimate.source == .reference ? Color.orange : Color.secondary)
                            .help(r.estimate.note ?? "")
                    }
                }
                .width(min: 90, ideal: 120)
                TableColumn("Mined / day") { r in
                    Text(r.coinsPerDay > 0 ? Format.coins(r.coinsPerDay, ticker: r.option.coinTag) : "—").monospacedDigit()
                }
                .width(min: 90, ideal: 120)
                TableColumn("Net / day") { r in
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Format.usd(r.netUSDPerDay)).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(r.netUSDPerDay >= 0 ? Color.green : Color.red)
                        Text("\(Format.usd(r.grossUSDPerDay)) − \(Format.usd(r.powerUSDPerDay)) power")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .width(min: 110, ideal: 150)
                TableColumn("24h volume") { r in
                    Text(r.volumeBTC.map { String(format: "%.2f BTC", $0) } ?? "—").monospacedDigit()
                        .foregroundStyle((r.volumeBTC ?? 0) < coordinator.settings.minimumLiquidityBTC ? Color.orange : Color.primary)
                }
                .width(min: 70, ideal: 90)
                TableColumn("Status") { r in
                    Label(r.status.label, systemImage: r.isEligible ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(r.isEligible ? Color.green : Color.secondary)
                        .font(.caption)
                }
                .width(min: 110, ideal: 150)
                TableColumn("") { r in
                    let running = coordinator.engines.contains { $0.job?.option == r.option && $0.isMining }
                    if running {
                        Text("Mining").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    } else {
                        Button("Mine") { coordinator.mine(r.option) }
                            .disabled(!r.isEligible)
                    }
                }
                .width(56)
            }
            footer
        }
        .padding(18)
    }

    private func summary(best: MiningPlan) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Most profitable right now").font(.caption).foregroundStyle(.secondary)
                Text(best.summary).font(.headline)
                Text("\(Format.usd(best.netUSDPerDay))/day net · \(Format.usd(best.netUSDPerDay * 30.4375))/month")
                    .font(.callout).foregroundStyle(best.netUSDPerDay >= 0 ? Color.green : Color.red)
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
                        Button(role: .cancel) { coordinator.cancelBenchmark() } label: { Label("Cancel benchmark", systemImage: "xmark") }
                    } else {
                        Button { coordinator.runBenchmark() } label: { Label("Benchmark this Mac", systemImage: "speedometer") }
                            .help("Runs each engine for ~2 minutes on its best ready coin and records hashrate and power")
                    }
                }
                if let progress = coordinator.benchmarkProgress {
                    ProgressView(value: progress).frame(width: 200)
                }
                Toggle("Show coins that aren't ready", isOn: Binding(get: { uiState.showIneligibleCoins }, set: { uiState.showIneligibleCoins = $0 })).toggleStyle(.checkbox).font(.caption)
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
            Text("Hashrates marked cryptominingonmacs.com are reference results for your chip until this Mac is benchmarked or has mined for 5 minutes.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
