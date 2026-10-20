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

struct MinerSettings: Codable, Equatable {
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

    var cpuConfigSignature: String {
        [xmrWallet, xmrPool, String(xmrPoolTLS), cpuPreset.rawValue, String(cpuCustomThreads),
         String(cpuPriority), String(cpuYield), workerName].joined(separator: "|")
    }

    var gpuConfigSignature: String {
        [rvnWallet, rvnPool, workerName].joined(separator: "|")
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
