import Foundation
import Observation

/// Owns both engines and decides, every few seconds, which should be running
/// based on the user's Start/Stop choice, settings and the pause rules.
@MainActor
@Observable
final class MiningCoordinator {
    let store: SettingsStore
    let cpu = XMRigController()
    let gpu = KawpowController()
    let system = SystemMonitor()
    let market = MarketDataService()
    let hardware = HardwareInfo.current

    private(set) var wantsMining = false
    private(set) var cpuBlockReason: String?
    private(set) var gpuBlockReason: String?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sleepActivity: NSObjectProtocol?

    var settings: MinerSettings { store.settings }
    var isMining: Bool { cpu.isMining || gpu.isMining }

    init(store: SettingsStore) {
        self.store = store
        system.start { [weak self] in self?.isMining ?? false }
        market.start { [weak self] in self?.store.settings ?? MinerSettings() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.evaluate()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        if store.settings.startMiningOnLaunch { start() }
    }

    func start() { wantsMining = true; evaluate() }
    func stop() { wantsMining = false; evaluate() }
    func toggle() { wantsMining ? stop() : start() }

    func shutdown() {
        loop?.cancel()
        cpu.stop()
        gpu.stop()
        updateSleepAssertion(active: false)
    }

    // MARK: - Rules

    private func evaluate() {
        let s = settings
        cpuBlockReason = blockReason(enabled: s.cpuEnabled, wallet: s.xmrWallet, validator: WalletValidator.isMonero, engine: AppPaths.xmrigExecutable, coin: .xmr)
        gpuBlockReason = blockReason(enabled: s.gpuEnabled, wallet: s.rvnWallet, validator: WalletValidator.isRavencoin, engine: AppPaths.kawpowExecutable, coin: .rvn)

        if wantsMining && cpuBlockReason == nil {
            if !cpu.isMining && cpu.process.state == .stopped {
                cpu.start(settings: s, hardware: hardware)
            } else if cpu.activeSignature != nil && cpu.activeSignature != s.cpuConfigSignature {
                cpu.start(settings: s, hardware: hardware) // settings changed → restart with new config
            }
        } else if cpu.activeSignature != nil {
            cpu.stop()
        }

        if wantsMining && gpuBlockReason == nil {
            if !gpu.isMining && gpu.process.state == .stopped {
                gpu.start(settings: s)
            } else if gpu.activeSignature != nil && gpu.activeSignature != s.gpuConfigSignature {
                gpu.start(settings: s)
            }
        } else if gpu.activeSignature != nil {
            gpu.stop()
        }

        updateSleepAssertion(active: s.preventSleep && (cpu.activeSignature != nil || gpu.activeSignature != nil))
    }

    private func blockReason(enabled: Bool, wallet: String, validator: (String) -> Bool,
                             engine: URL, coin: Coin) -> String? {
        let s = settings
        if !enabled { return "Disabled in Settings" }
        if wallet.trimmingCharacters(in: .whitespaces).isEmpty { return "Add your \(coin.ticker) wallet address in Settings" }
        if !validator(wallet) { return "\(coin.ticker) wallet address doesn't look valid" }
        if !FileManager.default.isExecutableFile(atPath: engine.path) { return "Engine missing – rebuild with scripts/build-app.sh" }
        if !wantsMining { return nil }
        if s.pauseOnBattery && system.onBattery { return "Paused – running on battery" }
        if s.pauseOnThermalPressure && (system.thermalState == .serious || system.thermalState == .critical) {
            return "Paused – thermal pressure \(system.thermalLabel.lowercased())"
        }
        if s.idleOnly && system.idleSeconds < Double(max(1, s.idleMinutes) * 60) {
            return "Waiting – mines after \(s.idleMinutes) min idle"
        }
        return nil
    }

    private func updateSleepAssertion(active: Bool) {
        if active, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "Crypto mining in progress")
        } else if !active, let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    // MARK: - Earnings

    /// Splits the measured (or estimated) power between CPU and GPU in proportion to the estimates.
    var allocatedWatts: (cpu: Double, gpu: Double) {
        let s = settings
        let estCPU = cpu.isMining ? s.cpuWattsEstimate : 0
        let estGPU = gpu.isMining ? s.gpuWattsEstimate : 0
        let estimateTotal = estCPU + estGPU
        guard estimateTotal > 0 else { return (0, 0) }

        switch s.powerSource {
        case .manual:
            return (estCPU, estGPU)
        case .measuredTotal, .measuredIncremental:
            guard let measured = system.systemWatts else { return (estCPU, estGPU) }
            var watts = measured
            if s.powerSource == .measuredIncremental {
                guard let baseline = system.idleBaselineWatts else { return (estCPU, estGPU) }
                watts = max(0, measured - baseline)
            }
            return (watts * estCPU / estimateTotal, watts * estGPU / estimateTotal)
        }
    }

    var powerSourceDescription: String {
        let s = settings
        switch s.powerSource {
        case .manual: return "Manual estimates"
        case .measuredTotal:
            return system.systemWatts == nil ? "Sensor unavailable – using estimates" : "Measured whole-Mac power"
        case .measuredIncremental:
            if system.systemWatts == nil { return "Sensor unavailable – using estimates" }
            if system.idleBaselineWatts == nil { return "Learning idle baseline – using estimates for now" }
            return "Measured power above idle baseline (\(Format.watts(system.idleBaselineWatts)))"
        }
    }

    var earnings: EarningsSnapshot {
        let s = settings
        let watts = allocatedWatts
        let xmr = CoinEarnings(
            coin: .xmr,
            hashrate: cpu.effectiveHashrate,
            coinsPerSecond: EarningsCalculator.coinsPerSecond(
                coin: .xmr, hashrate: cpu.effectiveHashrate, network: market.network[.xmr],
                poolFeePercent: s.xmrPoolFeePercent, devFeePercent: s.xmrDevFeePercent),
            priceUSD: market.prices[.xmr],
            watts: watts.cpu,
            network: market.network[.xmr])
        let rvn = CoinEarnings(
            coin: .rvn,
            hashrate: gpu.effectiveHashrate,
            coinsPerSecond: EarningsCalculator.coinsPerSecond(
                coin: .rvn, hashrate: gpu.effectiveHashrate, network: market.network[.rvn],
                poolFeePercent: s.rvnPoolFeePercent, devFeePercent: 0),
            priceUSD: market.prices[.rvn],
            watts: watts.gpu,
            network: market.network[.rvn])
        return EarningsSnapshot(coins: [xmr, rvn],
                                electricityUSDPerKWh: s.electricityUSDPerKWh,
                                totalWatts: watts.cpu + watts.gpu)
    }
}

enum WalletValidator {
    private static let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    /// Standard (4…), subaddress (8…) = 95 chars; integrated = 106 chars.
    static func isMonero(_ address: String) -> Bool {
        let a = address.trimmingCharacters(in: .whitespaces)
        guard let first = a.first, first == "4" || first == "8" else { return false }
        return (a.count == 95 || a.count == 106) && a.allSatisfy { base58.contains($0) }
    }

    /// Ravencoin P2PKH addresses start with R and are 34 characters.
    static func isRavencoin(_ address: String) -> Bool {
        let a = address.trimmingCharacters(in: .whitespaces)
        return a.first == "R" && a.count == 34 && a.allSatisfy { base58.contains($0) }
    }
}
