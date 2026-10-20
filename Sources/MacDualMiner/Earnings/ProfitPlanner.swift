import Foundation
import Observation

/// Where a hashrate figure in the profit check came from.
enum HashrateSource: String, Codable {
    case live, benchmark, reference, none

    var label: String {
        switch self {
        case .live: return "Live"
        case .benchmark: return "Benchmarked"
        case .reference: return "cryptominingonmacs.com"
        case .none: return "Not measured"
        }
    }
}

struct BenchmarkResult: Codable, Equatable {
    var cpuHashrate: Double
    var gpuHashrate: Double
    var watts: Double?
    var date: Date
    var coinTag: String
    var fromLiveMining: Bool
}

/// Measured hashrate (and power) per engine on this Mac, persisted between launches.
@MainActor
@Observable
final class BenchmarkStore {
    private(set) var results: [EngineAlgo: BenchmarkResult] = [:]
    @ObservationIgnored private let url: URL

    init(url: URL = AppPaths.benchmarksFile) {
        self.url = url
        if let data = try? Data(contentsOf: url) { results = Self.decode(data) }
    }

    private struct StoredFile: Codable {
        var version: Int
        var results: [String: BenchmarkResult]
    }

    /// Version 3 files are taken as they are. Version 2 (0.3.4–0.3.5) kawpow-metal results could include the
    /// bogus first-batch reading of each job, so those are dropped. Older files (a bare dictionary, 0.2.0–0.3.3)
    /// may hold live readings taken while CPU and GPU mined together, so only their dedicated benchmarks are kept
    /// (minus kawpow-metal for the same reason).
    nonisolated static func decode(_ data: Data) -> [EngineAlgo: BenchmarkResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var out: [EngineAlgo: BenchmarkResult] = [:]
        if let file = try? decoder.decode(StoredFile.self, from: data), file.version >= 2 {
            for (key, value) in file.results {
                if let pair = EngineAlgo(key: key), file.version >= 3 || pair.engine != .kawpow { out[pair] = value }
            }
        } else if let legacy = try? decoder.decode([String: BenchmarkResult].self, from: data) {
            for (key, value) in legacy where !value.fromLiveMining {
                if let pair = EngineAlgo(key: key), pair.engine != .kawpow { out[pair] = value }
            }
        }
        return out
    }

    func record(_ result: BenchmarkResult, for engine: EngineAlgo) {
        // A dedicated benchmark always wins; live readings blend in slowly and never overwrite a fresh benchmark.
        if result.fromLiveMining, let existing = results[engine] {
            if !existing.fromLiveMining, Date().timeIntervalSince(existing.date) < 86_400 { return }
            var blended = result
            blended.cpuHashrate = existing.cpuHashrate * 0.7 + result.cpuHashrate * 0.3
            blended.gpuHashrate = existing.gpuHashrate * 0.7 + result.gpuHashrate * 0.3
            if let w = result.watts { blended.watts = (existing.watts ?? w) * 0.7 + w * 0.3 } else { blended.watts = existing.watts }
            results[engine] = blended
        } else {
            results[engine] = result
        }
        save()
    }

    func clear() { results.removeAll(); save() }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let raw = Dictionary(uniqueKeysWithValues: results.map { ($0.key.key, $0.value) })
        guard let data = try? encoder.encode(StoredFile(version: 3, results: raw)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Hashrate an engine is expected to deliver on this Mac.
struct HashrateEstimate: Equatable {
    var cpu: Double
    var gpu: Double
    var watts: Double?
    var source: HashrateSource
    var note: String?
    var total: Double { cpu + gpu }
}

enum OptionStatus: Equatable {
    case ready
    case needsSetup(String)
    case engineDisabled
    case engineMissing
    case lowLiquidity
    case lagging
    case noMarketData
    case noHashrate

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .needsSetup(let why): return why
        case .engineDisabled: return "Engine turned off"
        case .engineMissing: return "Engine not installed"
        case .lowLiquidity: return "Too little trading volume"
        case .lagging: return "Network data stale"
        case .noMarketData: return "No market data"
        case .noHashrate: return "Benchmark needed"
        }
    }
}

struct RankedOption: Identifiable, Equatable {
    var option: MiningOption
    var coinName: String
    var algorithm: Algorithm
    var estimate: HashrateEstimate
    var coinsPerDay: Double
    var priceUSD: Double?
    var grossUSDPerDay: Double
    var powerUSDPerDay: Double
    var watts: Double
    var volumeBTC: Double?
    var feePercent: Double
    var status: OptionStatus
    var experimental: Bool

    var id: String { option.id }
    var netUSDPerDay: Double { grossUSDPerDay - powerUSDPerDay }
    var devices: Set<Device> { option.engine.devices }
    var isEligible: Bool { status == .ready }
}

/// Which engines/coins run together. Either one CPU option + one GPU option, or one CPU+GPU option.
struct MiningPlan: Equatable {
    var options: [MiningOption]
    var netUSDPerDay: Double

    static let empty = MiningPlan(options: [], netUSDPerDay: 0)

    var summary: String {
        options.isEmpty ? "Nothing ready to mine" :
            options.map { "\($0.engine.deviceLabel) → \($0.coinTag) (\($0.engine.displayName))" }.joined(separator: " · ")
    }

    func option(on device: Device) -> MiningOption? { options.first { $0.engine.devices.contains(device) } }
}

/// Plain data in, so ranking is pure and unit-testable.
struct ProfitInputs {
    var settings: MinerSettings
    var markets: [String: CoinMarket]          // keyed by coin tag
    var btcUSD: Double?
    var estimates: [EngineAlgo: HashrateEstimate]
    var installed: Set<EngineKind>
}

enum ProfitPlanner {
    /// Every coin the bundled engines can mine, ranked by net USD/day (best first).
    static func rank(_ input: ProfitInputs) -> [RankedOption] {
        let s = input.settings
        let rows: [RankedOption] = MiningOption.all.compactMap { option in
            guard let coin = option.coin else { return nil }
            let estimate = input.estimates[option.engineAlgo] ?? HashrateEstimate(cpu: 0, gpu: 0, watts: nil, source: .none, note: nil)
            let market = input.markets[coin.tag]
            let pool = s.pool(for: coin)
            let poolFee = pool?.feePercent ?? 1
            let keep = (1 - poolFee / 100) * (1 - option.engine.devFeePercent / 100)
            let coinsPerDay = (market?.coinsPerSecond(hashrate: estimate.total, useDayAverages: s.useDayAverages) ?? 0) * 86_400 * keep
            let price = input.btcUSD.flatMap { btc in market?.priceUSD(btcUSD: btc, useDayAverages: s.useDayAverages) }
            let gross = coinsPerDay * (price ?? 0)
            let watts = estimate.watts ?? wattsEstimate(option.engine, settings: s)
            let power = watts / 1000 * 24 * s.electricityUSDPerKWh

            let status: OptionStatus
            if !s.isEngineEnabled(option.engine) { status = .engineDisabled }
            else if !input.installed.contains(option.engine) { status = .engineMissing }
            else if market == nil || price == nil { status = .noMarketData }
            else if market?.lagging == true { status = .lagging }
            else if (market?.volumeBTC ?? 0) < s.minimumLiquidityBTC { status = .lowLiquidity }
            else if estimate.total <= 0 { status = .noHashrate }
            else if let problem = s.readinessProblem(option) { status = .needsSetup(problem) }
            else { status = .ready }

            return RankedOption(option: option, coinName: coin.name, algorithm: coin.algorithm, estimate: estimate,
                                coinsPerDay: coinsPerDay, priceUSD: price, grossUSDPerDay: gross,
                                powerUSDPerDay: power, watts: watts, volumeBTC: market?.volumeBTC,
                                feePercent: poolFee + option.engine.devFeePercent, status: status,
                                experimental: coin.experimental)
        }
        return rows.sorted { a, b in
            if a.isEligible != b.isEligible { return a.isEligible }
            return a.netUSDPerDay > b.netUSDPerDay
        }
    }

    /// Best combination of eligible options.
    static func bestPlan(_ ranked: [RankedOption], skipUnprofitable: Bool) -> MiningPlan {
        let eligible = ranked.filter { $0.isEligible && (!skipUnprofitable || $0.netUSDPerDay > 0) }
        let cpu = eligible.filter { $0.devices == [.cpu] }.max { $0.netUSDPerDay < $1.netUSDPerDay }
        let gpu = eligible.filter { $0.devices == [.gpu] }.max { $0.netUSDPerDay < $1.netUSDPerDay }
        let both = eligible.filter { $0.devices.count == 2 }.max { $0.netUSDPerDay < $1.netUSDPerDay }

        let split = [cpu, gpu].compactMap { $0 }
        let splitNet = split.reduce(0) { $0 + $1.netUSDPerDay }
        if let both, both.netUSDPerDay > splitNet || split.isEmpty {
            return MiningPlan(options: [both.option], netUSDPerDay: both.netUSDPerDay)
        }
        return MiningPlan(options: split.map(\.option), netUSDPerDay: splitNet)
    }

    /// Devices whose ready coins all lose money (and that have at least one ready coin).
    static func losingDevices(_ ranked: [RankedOption]) -> Set<Device> {
        var result: Set<Device> = []
        for device in Device.allCases {
            let ready = ranked.filter { $0.isEligible && $0.devices.contains(device) }
            if !ready.isEmpty && ready.allSatisfy({ $0.netUSDPerDay <= 0 }) { result.insert(device) }
        }
        return result
    }

    /// Net USD/day of an arbitrary plan using the same ranking numbers.
    static func value(of options: [MiningOption], in ranked: [RankedOption]) -> Double {
        options.compactMap { o in ranked.first { $0.option == o }?.netUSDPerDay }.reduce(0, +)
    }

    /// Hysteresis: switch only when the best plan beats the current one by the margin.
    static func shouldSwitch(currentNet: Double, bestNet: Double, marginPercent: Double) -> Bool {
        let gain = bestNet - currentNet
        guard gain > 0 else { return false }
        let base = max(abs(currentNet), 0.01)   // avoid dividing by ~0 when the current plan earns nothing
        return gain / base * 100 >= marginPercent
    }

    /// Manual watt estimates are for full power; scale them to the CPU/GPU power levels.
    static func wattsEstimate(_ engine: EngineKind, settings s: MinerSettings) -> Double {
        let cpu = s.cpuWattsEstimate * s.cpuPowerFactor
        let gpu = s.gpuWattsEstimate * s.gpuPowerFactor
        switch engine.devices.count {
        case 2: return cpu + gpu
        default: return engine.devices.contains(.cpu) ? cpu : gpu
        }
    }
}
