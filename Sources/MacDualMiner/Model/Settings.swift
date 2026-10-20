import Foundation
import Observation

/// How many CPU threads XMRig should use. The M5 Max has 18 cores (6 super + 12 performance, no efficiency cores).
enum CPUPreset: String, Codable, CaseIterable, Identifiable {
    case auto, full, balanced, light, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto (XMRig decides)"
        case .full: return "Full – every core"
        case .balanced: return "Balanced – ⅔ of cores (best with GPU on)"
        case .light: return "Light – ⅓ of cores"
        case .custom: return "Custom"
        }
    }

    /// Thread count for a given core count; nil means "let XMRig auto-configure".
    func threads(totalCores: Int, custom: Int) -> Int? {
        switch self {
        case .auto: return nil
        case .full: return max(1, totalCores)
        case .balanced: return max(1, totalCores * 2 / 3)
        case .light: return max(1, totalCores / 3)
        case .custom: return min(max(1, custom), max(1, totalCores))
        }
    }
}

/// Where the earnings calculator gets electricity usage from.
enum PowerSourceMode: String, Codable, CaseIterable, Identifiable {
    case measuredIncremental, measuredTotal, manual
    var id: String { rawValue }

    var label: String {
        switch self {
        case .measuredIncremental: return "Measured – extra power over idle (most realistic)"
        case .measuredTotal: return "Measured – whole-Mac power"
        case .manual: return "Manual watt estimates"
        }
    }
}

/// What decides which coin each part of the chip mines.
enum SwitchingMode: String, Codable, CaseIterable, Identifiable {
    case auto, recommend, manual
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto-switch to the most profitable coin"
        case .recommend: return "Recommend only – I'll switch myself"
        case .manual: return "Manual – always mine my chosen coins"
        }
    }
}

/// A pool the user typed in for a coin.
struct CustomPool: Codable, Equatable {
    var address = ""
    var tls = false
    var feePercent = 1.0
    var userTemplate = "{wallet}.{worker}"
}

struct MinerSettings: Codable, Equatable {
    // MARK: Coins, wallets, pools
    /// Receiving address per coin tag ("XMR", "RVN", …).
    var wallets: [String: String] = [:]
    /// Kryptex username/email – used for any coin on a Kryptex pool that has no wallet of its own.
    var kryptexAccount = ""
    /// Chosen pool preset id per coin, or "custom".
    var poolChoice: [String: String] = [:]
    var customPools: [String: CustomPool] = [:]

    // MARK: App
    var checkForUpdates = true
    /// NiceHash-style dark interface; off = follow the system appearance.
    var darkInterface = true

    // MARK: Switching
    var switchingMode: SwitchingMode = .auto
    var manualCPUOption = "xmrig:XMR"
    var manualGPUOption = "kawpow:RVN"
    var switchCheckMinutes = 15
    var switchMarginPercent = 10.0
    var minimumRunMinutes = 20
    var minimumLiquidityBTC = 0.5
    var useDayAverages = true
    var ethminerEnabled = true
    var uselethEnabled = true
    var uselethThreads = 0          // 0 = one per CPU core

    // MARK: Power levels (1…10)
    /// CPU: share of cores mining (7 ≈ 13 of 18 cores on an M5 Max).
    var cpuPowerLevel = 7
    /// GPU: share of each second the GPU engine runs (10 = flat out).
    var gpuPowerLevel = 10

    var cpuPowerFactor: Double { Double(min(10, max(1, cpuPowerLevel))) / 10 }
    var gpuPowerFactor: Double { Double(min(10, max(1, gpuPowerLevel))) / 10 }

    func cpuThreads(totalCores: Int) -> Int { max(1, Int((Double(totalCores) * cpuPowerFactor).rounded())) }

    // MARK: CPU – XMRig / Monero
    var cpuEnabled = true
    var xmrWallet = ""
    var xmrPool = "pool.supportxmr.com:443"
    var xmrPoolTLS = true
    var xmrPoolFeePercent = 0.6
    var cpuPreset: CPUPreset = .balanced
    var cpuCustomThreads = 12
    var cpuPriority = 1          // 0 (idle) … 5 (highest)
    var cpuYield = true          // let other apps take CPU time first

    // MARK: GPU – kawpow-metal / Ravencoin
    var gpuEnabled = true
    var rvnWallet = ""
    var rvnPool = "rvn.2miners.com:6060"
    var rvnPoolFeePercent = 1.0

    // MARK: Shared
    var workerName = "m5max"

    // MARK: Rules
    var pauseOnBattery = true
    var pauseOnThermalPressure = true
    var idleOnly = false
    var idleMinutes = 5
    var preventSleep = true
    var startMiningOnLaunch = false

    // MARK: Earnings calculator
    var electricityUSDPerKWh = 0.17
    var powerSource: PowerSourceMode = .measuredIncremental
    var cpuWattsEstimate = 55.0
    var gpuWattsEstimate = 60.0
    var xmrDevFeePercent = 1.0   // XMRig's built-in donation (minimum 1% in official builds)
    var xmrDifficultyOverride = 0.0
    var rvnDifficultyOverride = 0.0
    var xmrNodeURL = "http://xmr-node.cakewallet.com:18081/json_rpc"
    var customRVNStatsURL = ""
    var marketRefreshSeconds = 60

    /// Decode stored JSON on top of defaults, so settings files from older versions keep working.
    static func load(from data: Data) -> MinerSettings {
        guard
            let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let defaultsData = try? JSONEncoder().encode(MinerSettings()),
            var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return MinerSettings() }
        for (key, value) in stored { merged[key] = value }
        guard
            let mergedData = try? JSONSerialization.data(withJSONObject: merged),
            let settings = try? JSONDecoder().decode(MinerSettings.self, from: mergedData)
        else { return MinerSettings() }
        return settings
    }

    /// Settings that affect how XMRig runs (beyond the job itself).
    var cpuTuningSignature: String {
        [String(cpuPowerLevel), String(cpuPriority), String(cpuYield), String(uselethThreads)]
            .joined(separator: "|")
    }

    // MARK: Wallets & pools

    /// The address to mine a coin to. Monero and Ravencoin fall back to the original single-coin fields.
    func wallet(for tag: String) -> String {
        if let w = wallets[tag]?.trimmingCharacters(in: .whitespaces), !w.isEmpty { return w }
        switch tag {
        case "XMR": return xmrWallet.trimmingCharacters(in: .whitespaces)
        case "RVN": return rvnWallet.trimmingCharacters(in: .whitespaces)
        default: return ""
        }
    }

    /// The pool selected for a coin: the user's choice, else the coin's first preset.
    func pool(for coin: CoinSpec) -> PoolPreset? {
        let choice = poolChoice[coin.tag]
        if choice == "custom", let custom = customPools[coin.tag], !custom.address.isEmpty {
            return PoolPreset(id: "custom", name: "Custom", address: custom.address, tls: custom.tls,
                              feePercent: custom.feePercent, userTemplate: custom.userTemplate)
        }
        if let choice, let preset = coin.pools.first(where: { $0.id == choice }) { return applyLegacy(preset, coin: coin) }
        if let first = coin.pools.first { return applyLegacy(first, coin: coin) }
        if let custom = customPools[coin.tag], !custom.address.isEmpty {
            return PoolPreset(id: "custom", name: "Custom", address: custom.address, tls: custom.tls,
                              feePercent: custom.feePercent, userTemplate: custom.userTemplate)
        }
        return nil
    }

    /// v0.1 stored the Monero/Ravencoin pool as free text – honour it for the default preset.
    private func applyLegacy(_ preset: PoolPreset, coin: CoinSpec) -> PoolPreset {
        var p = preset
        if coin.tag == "XMR", preset.id == "supportxmr" {
            p.address = xmrPool; p.tls = xmrPoolTLS; p.feePercent = xmrPoolFeePercent
        } else if coin.tag == "RVN", preset.id == "2miners" {
            p.address = rvnPool; p.feePercent = rvnPoolFeePercent
        }
        return p
    }

    /// Why a mining option can't run yet, or nil if it's ready.
    func readinessProblem(_ option: MiningOption) -> String? {
        guard let coin = option.coin else { return "Unknown coin" }
        guard let pool = pool(for: coin) else { return "Needs a pool" }
        if option.engine == .useleth && pool.tls { return "UselethMiner can't use TLS pools" }
        if option.engine == .kawpow && pool.tls { return "kawpow-metal can't use TLS pools" }
        let hasWallet = !wallet(for: coin.tag).isEmpty
        let canUseKryptex = pool.acceptsKryptexAccount && !kryptexAccount.trimmingCharacters(in: .whitespaces).isEmpty
        if !hasWallet && !canUseKryptex { return "Needs a \(coin.tag) wallet" }
        return nil
    }

    /// Resolve an option to a concrete job, or nil if it isn't ready.
    func job(for option: MiningOption) -> MiningJob? {
        guard readinessProblem(option) == nil, let coin = option.coin, let pool = pool(for: coin) else { return nil }
        let own = wallet(for: coin.tag)
        let payTo = own.isEmpty ? kryptexAccount.trimmingCharacters(in: .whitespaces) : own
        let worker = workerName.isEmpty ? "mac" : workerName
        return MiningJob(option: option, poolAddress: pool.address, tls: pool.tls, poolFeePercent: pool.feePercent,
                         login: PoolLogin.build(template: pool.userTemplate, wallet: payTo, worker: worker),
                         worker: worker)
    }

    func isEngineEnabled(_ engine: EngineKind) -> Bool {
        switch engine {
        case .xmrig: return cpuEnabled
        case .kawpow: return gpuEnabled
        case .ethminer: return gpuEnabled && ethminerEnabled
        case .useleth: return cpuEnabled && gpuEnabled && uselethEnabled
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    var settings: MinerSettings {
        didSet { if settings != oldValue { save() } }
    }

    private let url: URL

    init(url: URL = AppPaths.settingsFile) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            settings = MinerSettings.load(from: data)
        } else {
            settings = MinerSettings()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
