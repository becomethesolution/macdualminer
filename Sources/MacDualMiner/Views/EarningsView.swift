import SwiftUI

/// Real-time profitability: live hashrate × live network difficulty × live USD price, minus fees and electricity.
struct EarningsView: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        let e = coordinator.earnings
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headline(e)
                Card(title: "Projection at current hashrate", systemImage: "chart.line.uptrend.xyaxis") {
                    table(e)
                }
                HStack(alignment: .top, spacing: 14) {
                    ForEach(e.coins, id: \.tag) { coinCard($0) }
                }
                assumptions(e)
            }
            .padding(18)
        }
    }

    private func headline(_ e: EarningsSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading) {
                Text("Net per day").font(.caption).foregroundStyle(.secondary)
                Text(Format.usd(e.net(.day)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(e.netUSDPerSecond >= 0 ? Color.green : Color.red)
                    .monospacedDigit()
            }
            VStack(alignment: .leading) {
                Text("Gross per day").font(.caption).foregroundStyle(.secondary)
                Text(Format.usd(e.gross(.day))).font(.title2.weight(.semibold)).monospacedDigit()
            }
            VStack(alignment: .leading) {
                Text("Electricity per day").font(.caption).foregroundStyle(.secondary)
                Text(Format.usd(e.power(.day))).font(.title2.weight(.semibold)).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    Task { await coordinator.market.refresh(settings: coordinator.settings) }
                } label: {
                    Label("Refresh prices", systemImage: "arrow.clockwise")
                }
                .disabled(coordinator.market.isRefreshing)
                if let updated = coordinator.market.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func table(_ e: EarningsSnapshot) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text("Period").gridColumnAlignment(.leading)
                ForEach(e.coins, id: \.tag) { c in Text("\(c.tag) mined") }
                Text("Gross USD")
                Text("Electricity")
                Text("Net USD")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(Period.allCases) { period in
                GridRow {
                    Text(period.rawValue).gridColumnAlignment(.leading)
                    ForEach(e.coins, id: \.tag) { c in
                        Text(c.hashrate > 0 ? Format.coins(c.coinsPerSecond * period.seconds, ticker: c.tag) : "—")
                    }
                    Text(Format.usd(e.gross(period)))
                    Text(Format.usd(-e.power(period))).foregroundStyle(.secondary)
                    Text(Format.usd(e.net(period)))
                        .fontWeight(.semibold)
                        .foregroundStyle(e.net(period) >= 0 ? Color.green : Color.red)
                }
                .monospacedDigit()
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func coinCard(_ c: CoinEarnings) -> some View {
        Card(title: "\(c.name) (\(c.tag))", systemImage: c.engine.devices.contains(.cpu) ? "cpu" : "square.stack.3d.up") {
            StatRow(label: "Engine · algorithm", value: "\(c.engine.displayName) · \(c.algorithm.rawValue)")
            StatRow(label: "Your hashrate", value: Format.hashrate(c.hashrate))
            StatRow(label: "Price", value: Format.usd(c.priceUSD))
            StatRow(label: "Network hashrate", value: Format.hashrate(c.networkHashrate))
            StatRow(label: "Your share of network", value: share(c))
            StatRow(label: "Block reward", value: c.blockReward.map { Format.coins($0, ticker: c.tag) } ?? "—")
            StatRow(label: "Power charged", value: Format.watts(c.watts))
            StatRow(label: "Gross per day", value: Format.usd(c.usdPerSecond.map { $0 * Period.day.seconds }))
            if let source = c.dataSource {
                Text("Network data: \(source)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func share(_ c: CoinEarnings) -> String {
        guard let total = c.networkHashrate, total > 0, c.hashrate > 0 else { return "—" }
        return String(format: "%.8f%%", c.hashrate / total * 100)
    }

    private func assumptions(_ e: EarningsSnapshot) -> some View {
        let s = coordinator.settings
        return Card(title: "How this is calculated", systemImage: "info.circle") {
            Text(verbatim: "Coins per second = your hashrate ÷ network hashrate × block reward ÷ block time, minus the pool fee and the engine's dev fee (XMRig and UselethMiner keep 1%). Network numbers come from WhatToMine, prices from WhatToMine's BTC rate × CoinGecko's BTC price. These are expected values: pool payouts vary with luck and difficulty changes.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            StatRow(label: "Electricity rate", value: Format.usd(s.electricityUSDPerKWh) + "/kWh")
            StatRow(label: "Power figure", value: coordinator.powerSourceDescription)
            StatRow(label: "Watts charged to mining", value: Format.watts(e.totalWatts))
            if let breakEven = e.breakEvenUSDPerKWh {
                StatRow(label: "Break-even electricity price", value: Format.usd(breakEven) + "/kWh")
            }
            StatRow(label: "Prices from", value: coordinator.market.priceSource ?? "—")
            ForEach(coordinator.market.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if !coordinator.isMining {
                Text("Start mining to see live numbers – every figure here is driven by your actual hashrate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
