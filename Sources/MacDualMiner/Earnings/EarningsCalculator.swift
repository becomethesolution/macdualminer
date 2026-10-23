import Foundation

enum Coin: String, CaseIterable, Identifiable {
    case xmr, rvn
    var id: String { rawValue }
    var ticker: String { rawValue.uppercased() }
    var name: String { self == .xmr ? "Monero" : "Ravencoin" }
    var blockTimeSeconds: Double { self == .xmr ? 120 : 60 }
}

/// Live network numbers for one coin.
struct NetworkStats: Equatable {
    var difficulty: Double
    var blockReward: Double
    var height: Int?
    var source: String

    /// Expected hashes needed to find one block.
    func hashesPerBlock(for coin: Coin) -> Double {
        switch coin {
        case .xmr: return difficulty                 // CryptoNote difficulty = expected hashes per block
        case .rvn: return difficulty * 4_294_967_296 // Bitcoin-style difficulty × 2^32
        }
    }

    /// Implied total network hashrate (H/s), shown as a sanity check.
    func networkHashrate(for coin: Coin) -> Double {
        hashesPerBlock(for: coin) / coin.blockTimeSeconds
    }
}

enum Period: String, CaseIterable, Identifiable {
    case hour = "Hour", day = "Day", week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
    var seconds: Double {
        switch self {
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return 604_800
        case .month: return 2_629_800   // 30.4375 days
        case .year: return 31_557_600   // 365.25 days
        }
    }
}

/// What one running engine is earning right now.
struct CoinEarnings: Equatable {
    var tag: String
    var name: String
    var algorithm: Algorithm
    var engine: EngineKind
    var hashrate: Double          // H/s
    var coinsPerSecond: Double    // after pool + dev fees
    var priceUSD: Double?
    var watts: Double
    var networkHashrate: Double?  // H/s
    var blockReward: Double?
    var dataSource: String?

    var usdPerSecond: Double? { priceUSD.map { coinsPerSecond * $0 } }
    var isComputable: Bool { networkHashrate != nil && priceUSD != nil }
}

/// Everything the Earnings view needs, for one moment in time.
struct EarningsSnapshot: Equatable {
    var coins: [CoinEarnings]
    var electricityUSDPerKWh: Double
    var totalWatts: Double

    var grossUSDPerSecond: Double { coins.compactMap(\.usdPerSecond).reduce(0, +) }
    var powerUSDPerSecond: Double { totalWatts / 1000 / 3600 * electricityUSDPerKWh }
    var netUSDPerSecond: Double { grossUSDPerSecond - powerUSDPerSecond }

    func gross(_ p: Period) -> Double { grossUSDPerSecond * p.seconds }
    func power(_ p: Period) -> Double { powerUSDPerSecond * p.seconds }
    func net(_ p: Period) -> Double { netUSDPerSecond * p.seconds }

    /// Electricity price at which mining stops paying for itself.
    var breakEvenUSDPerKWh: Double? {
        guard totalWatts > 0 else { return nil }
        return grossUSDPerSecond / (totalWatts / 1000 / 3600)
    }
}

enum EarningsCalculator {
    /// Coins earned per second at a given hashrate, after pool fee and dev fee.
    static func coinsPerSecond(coin: Coin, hashrate: Double, network: NetworkStats?,
                               poolFeePercent: Double, devFeePercent: Double) -> Double {
        guard let network, hashrate > 0 else { return 0 }
        let hashesPerBlock = network.hashesPerBlock(for: coin)
        guard hashesPerBlock > 0, network.blockReward > 0 else { return 0 }
        let blocksPerSecond = hashrate / hashesPerBlock
        let gross = blocksPerSecond * network.blockReward
        let keep = (1 - clampPercent(poolFeePercent) / 100) * (1 - clampPercent(devFeePercent) / 100)
        return gross * keep
    }

    /// Ravencoin: 5000 RVN, halving every 2,100,000 blocks (1250 RVN since block 4,200,000).
    static func ravencoinReward(atHeight height: Int?) -> Double {
        guard let height, height >= 0 else { return 1250 }
        let halvings = height / 2_100_000
        guard halvings < 64 else { return 0 }
        return 5000 / pow(2, Double(halvings))
    }

    /// Monero has a permanent tail emission of 0.6 XMR per block (plus fees).
    static let moneroTailReward = 0.6

    private static func clampPercent(_ p: Double) -> Double { min(max(p, 0), 100) }
}

enum Format {
    static func hashrate(_ hs: Double?) -> String {
        guard let hs, hs > 0 else { return "—" }
        let units = ["H/s", "kH/s", "MH/s", "GH/s", "TH/s", "PH/s", "EH/s"]
        var value = hs
        var index = 0
        while value >= 1000 && index < units.count - 1 { value /= 1000; index += 1 }
        return String(format: value >= 100 ? "%.0f %@" : "%.2f %@", value, units[index])
    }

    static func usd(_ value: Double?) -> String {
        guard var value, value.isFinite else { return "—" }
        if abs(value) < 0.00005 { value = 0 }   // no "−$0.0000"
        let magnitude = abs(value)
        let digits = magnitude >= 100 ? 2 : magnitude >= 1 ? 2 : magnitude >= 0.01 ? 3 : 4
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    static func coins(_ value: Double, ticker: String) -> String {
        let magnitude = abs(value)
        let digits = magnitude >= 100 ? 2 : magnitude >= 1 ? 4 : 6
        return String(format: "%.\(digits)f %@", value, ticker)
    }

    static func number(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value < 10 ? 4 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f W", value)
    }
}
