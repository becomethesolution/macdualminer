import Foundation
import Observation

/// One coin's network numbers from WhatToMine.
struct CoinMarket: Equatable {
    var tag: String
    var name: String
    var algorithm: String
    var blockTime: Double          // seconds
    var blockReward: Double
    var blockReward24: Double?
    var networkHashrate: Double    // H/s
    var exchangeRateBTC: Double
    var exchangeRateBTC24: Double?
    var volumeBTC: Double?         // 24h exchange volume, in BTC
    var lagging: Bool

    /// Coins per second at `hashrate`, before fees.
    func coinsPerSecond(hashrate: Double, useDayAverages: Bool) -> Double {
        guard hashrate > 0, networkHashrate > 0, blockTime > 0 else { return 0 }
        let reward = useDayAverages ? (blockReward24 ?? blockReward) : blockReward
        return hashrate / networkHashrate * reward / blockTime
    }

    func priceUSD(btcUSD: Double, useDayAverages: Bool) -> Double {
        (useDayAverages ? (exchangeRateBTC24 ?? exchangeRateBTC) : exchangeRateBTC) * btcUSD
    }
}

enum WhatToMineParser {
    /// Parses coins.json / cpu.json. Skips NiceHash marketplace pseudo-coins.
    static func parse(_ data: Data) -> [CoinMarket] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let coins = root["coins"] as? [String: Any] else { return [] }
        return coins.compactMap { name, value in
            guard let c = value as? [String: Any], !name.hasPrefix("Nicehash"),
                  let tag = c["tag"] as? String, tag != "NICEHASH",
                  let algorithm = c["algorithm"] as? String,
                  let blockTime = num(c["block_time"]), let reward = num(c["block_reward"]),
                  let nethash = num(c["nethash"]), let rate = num(c["exchange_rate"]) else { return nil }
            return CoinMarket(tag: tag, name: name, algorithm: algorithm, blockTime: blockTime,
                              blockReward: reward, blockReward24: num(c["block_reward24"]),
                              networkHashrate: nethash, exchangeRateBTC: rate,
                              exchangeRateBTC24: num(c["exchange_rate24"]), volumeBTC: num(c["exchange_rate_vol"]),
                              lagging: (c["lagging"] as? Bool) ?? false)
        }
    }

    static func num(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}

/// Live multi-coin market data for the profit check.
@MainActor
@Observable
final class ProfitDataService {
    private(set) var markets: [String: CoinMarket] = [:]   // keyed by "TAG|Algorithm"
    private(set) var btcUSD: Double?
    private(set) var lastUpdated: Date?
    private(set) var problem: String?
    private(set) var isRefreshing = false

    @ObservationIgnored private var task: Task<Void, Never>?

    func start(interval: @escaping @MainActor () -> Int) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(max(120, interval() * 60 / 3)))
            }
        }
    }

    /// Market for a catalog coin (matched by ticker and algorithm, so e.g. QUAI-KawPow ≠ QUAI-SHA).
    func market(for coin: CoinSpec) -> CoinMarket? { markets["\(coin.tag)|\(coin.algorithm.rawValue)"] }
    func market(tag: String, algorithm: String) -> CoinMarket? { markets["\(tag)|\(algorithm)"] }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        async let gpu = MarketDataService.getData("https://whattomine.com/coins.json")
        async let cpu = MarketDataService.getData("https://whattomine.com/cpu.json")
        async let btc = MarketDataService.getJSON("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd")

        var merged: [String: CoinMarket] = [:]
        for data in [await gpu, await cpu].compactMap({ $0 }) {
            for m in WhatToMineParser.parse(data) { merged["\(m.tag)|\(m.algorithm)"] = m }
        }
        if let json = await btc as? [String: Any],
           let price = MarketDataService.number((json["bitcoin"] as? [String: Any])?["usd"]) {
            btcUSD = price
        }
        if !merged.isEmpty { markets = merged }
        problem = merged.isEmpty ? "Couldn't reach WhatToMine – profit check uses the last data it had" :
                  (btcUSD == nil ? "Couldn't fetch the BTC price" : nil)
        lastUpdated = Date()
    }
}
