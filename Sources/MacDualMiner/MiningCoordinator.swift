import Foundation
import Observation

/// Owns every engine and decides, every few seconds, what should be running: the user's Start/Stop choice,
/// the switching mode (auto / recommend / manual), the profit check and the pause rules.
@MainActor
@Observable
final class MiningCoordinator {
    let store: SettingsStore
    let xmrig = XMRigController()
    let kawpow = KawpowController()
    let ethminer = EthminerController()
    let useleth = UselethController()
    let system = SystemMonitor()
    let market = MarketDataService()      // XMR / RVN specific fallback data
    let profit = ProfitDataService()      // WhatToMine data for every coin
    let benchmarks = BenchmarkStore()
    let uselethInstaller = UselethInstaller()
    let history = EarningsHistory()
    let hardware = HardwareInfo.current

    private(set) var wantsMining = false
    private(set) var blockReasons: [Device: String] = [:]
    /// What the coordinator is trying to run right now.
    private(set) var activePlan = MiningPlan.empty
    /// A better plan than the active one (shown in recommend mode, or while auto waits out the minimum run time).
    private(set) var recommendedPlan: MiningPlan?
    private(set) var planStartedAt: Date?
    private(set) var lastSwitchCheck: Date?
    private(set) var switchLog: [String] = []
    private(set) var benchmarkStatus: String?
    private(set) var benchmarkProgress: Double?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var benchmarkTask: Task<Void, Never>?
    @ObservationIgnored private var benchmarkOption: MiningOption?
    @ObservationIgnored private var sleepActivity: NSObjectProtocol?
    @ObservationIgnored private var lastLiveRecord: [EngineAlgo: Date] = [:]

    var settings: MinerSettings { store.settings }
    var engines: [any MiningEngine] { [xmrig, kawpow, ethminer, useleth] }
    var isMining: Bool { engines.contains { $0.isMining } }
    var isBenchmarking: Bool { benchmarkTask != nil }

    func engine(_ kind: EngineKind) -> any MiningEngine {
        switch kind {
        case .xmrig: return xmrig
        case .kawpow: return kawpow
        case .ethminer: return ethminer
        case .useleth: return useleth
        }
    }

    /// The engine (if any) currently working on a part of the chip.
    func runningEngine(on device: Device) -> (any MiningEngine)? {
        engines.first { $0.job != nil && $0.kind.devices.contains(device) }
    }

    init(store: SettingsStore) {
        self.store = store
        system.start { [weak self] in self?.isMining ?? false }
        market.start { [weak self] in self?.store.settings ?? MinerSettings() }
        profit.start { [weak self] in self?.store.settings.switchCheckMinutes ?? 15 }
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
        benchmarkTask?.cancel()
        engines.forEach { $0.stop() }
        history.save()
        updateSleepAssertion(active: false)
    }

    /// Adopt a plan now (the "Switch" button and "Mine this" use this).
    func adopt(_ plan: MiningPlan, reason: String) {
        if settings.switchingMode != .auto {
            if let cpu = plan.option(on: .cpu) { store.settings.manualCPUOption = cpu.id }
            if let gpu = plan.option(on: .gpu) { store.settings.manualGPUOption = gpu.id }
        }
        setActive(plan, reason: reason)
        recommendedPlan = nil
        evaluate()
    }

    /// Mine one option on its device(s), keeping whatever runs on the other part of the chip.
    func mine(_ option: MiningOption) {
        var options = activePlan.options.filter { $0.engine.devices.isDisjoint(with: option.engine.devices) }
        options.append(option)
        if settings.switchingMode == .auto { store.settings.switchingMode = .manual }
        adopt(MiningPlan(options: options, netUSDPerDay: ProfitPlanner.value(of: options, in: ranked)),
              reason: "You chose \(option.label)")
        if !wantsMining { start() }
    }

    // MARK: - Profit check

    var ranked: [RankedOption] {
        var markets: [String: CoinMarket] = [:]
        for coin in CoinCatalog.coins { if let m = profit.market(for: coin) { markets[coin.tag] = m } }
        var estimates: [EngineAlgo: HashrateEstimate] = [:]
        for pair in EngineAlgo.all { estimates[pair] = estimate(for: pair) }
        let installed = Set(EngineKind.allCases.filter { FileManager.default.isExecutableFile(atPath: $0.executable.path) })
        return ProfitPlanner.rank(ProfitInputs(settings: settings, markets: markets, btcUSD: profit.btcUSD,
                                               estimates: estimates, installed: installed))
    }

    var bestPlan: MiningPlan { ProfitPlanner.bestPlan(ranked, skipUnprofitable: settings.pauseUnprofitable) }

    /// Devices left idle because every ready coin on them loses money after electricity.
    private(set) var unprofitableDevices: Set<Device> = []

    /// Live reading > this Mac's benchmark > cryptominingonmacs.com reference for this chip.
    func estimate(for pair: EngineAlgo) -> HashrateEstimate {
        let kind = pair.engine
        let e = engine(kind)
        if e.isMining, e.job?.option.engineAlgo == pair, e.totalHashrate > 0, let started = e.process.startedAt, Date().timeIntervalSince(started) > 90 {
            let w = allocatedWatts[kind]
            return HashrateEstimate(cpu: e.hashrate(for: .cpu), gpu: e.hashrate(for: .gpu),
                                    watts: settings.powerSource == .manual ? nil : w, source: .live, note: nil)
        }
        // Benchmarks are stored at full power (level 10); scale them to the current power levels.
        let cpuF = settings.cpuPowerFactor, gpuF = settings.gpuPowerFactor
        if let b = benchmarks.results[pair] {
            let w = b.watts.map { scaledWatts($0, kind: kind, cpu: cpuF, gpu: gpuF) }
            return HashrateEstimate(cpu: b.cpuHashrate * cpuF, gpu: b.gpuHashrate * gpuF, watts: w, source: .benchmark,
                                    note: "Measured \(b.date.formatted(date: .abbreviated, time: .shortened)) on \(b.coinTag), scaled to power level")
        }
        if let r = ReferenceHashrates.lookup(chip: hardware.chipName, engine: kind, algorithm: pair.algorithm) {
            let cpu = kind.devices.contains(.cpu) ? r.hashrate : 0
            let gpu = kind == .useleth ? (r.gpuHashrate ?? 0) : (kind.devices.contains(.gpu) ? r.hashrate : 0)
            return HashrateEstimate(cpu: cpu * cpuF, gpu: gpu * gpuF, watts: nil, source: .reference,
                                    note: r.note + " (full power, scaled to your power level)")
        }
        return HashrateEstimate(cpu: 0, gpu: 0, watts: nil, source: .none, note: nil)
    }

    /// Watts measured at full power, scaled to the current power levels (assumes power ∝ work).
    private func scaledWatts(_ watts: Double, kind: EngineKind, cpu: Double, gpu: Double) -> Double {
        switch kind.devices.count {
        case 2: return watts * (cpu + gpu) / 2
        default: return watts * (kind.devices.contains(.cpu) ? cpu : gpu)
        }
    }

    // MARK: - Rules

    private func evaluate() {
        let s = settings
        updateBlockReasons()
        let desired = desiredPlan()
        if desired.options != activePlan.options { setActive(desired, reason: nil) }

        // Work out each engine's job, then stop before start (GPU engines can't share the GPU).
        var wanted: [EngineKind: MiningJob] = [:]
        for option in activePlan.options where wantsMining || benchmarkOption != nil {
            guard s.isEngineEnabled(option.engine) || benchmarkOption == option,
                  option.engine.devices.allSatisfy({ blockReasons[$0] == nil }),
                  let job = s.job(for: option) else { continue }
            wanted[option.engine] = job
        }
        for e in engines where e.activeSignature != nil {
            guard let job = wanted[e.kind] else { e.stop(); continue }
            if e.activeSignature != expectedSignature(e.kind, job: job) { e.stop() }
        }
        for (kind, job) in wanted {
            let e = engine(kind)
            if e.activeSignature == nil && e.process.state == .stopped {
                e.start(job: job, settings: s, hardware: hardware)
            }
        }

        // GPU power level → duty cycle (CPU power level is applied as a thread count at start).
        kawpow.process.dutyCycle = s.gpuPowerFactor
        ethminer.process.dutyCycle = s.gpuPowerFactor
        useleth.process.dutyCycle = s.gpuPowerFactor
        xmrig.process.dutyCycle = 1

        recordLiveBenchmarks()
        recordHistory()
        updateSleepAssertion(active: s.preventSleep && engines.contains { $0.activeSignature != nil })
    }

    private func expectedSignature(_ kind: EngineKind, job: MiningJob) -> String {
        switch kind {
        case .xmrig, .useleth: return job.signature + "|" + settings.cpuTuningSignature
        case .kawpow, .ethminer: return job.signature
        }
    }

    private func manualPlan() -> MiningPlan {
        let s = settings
        let cpu = MiningOption(id: s.manualCPUOption)
        let gpu = MiningOption(id: s.manualGPUOption)
        if let combined = [cpu, gpu].compactMap({ $0 }).first(where: { $0.engine.devices.count == 2 }) {
            return MiningPlan(options: [combined], netUSDPerDay: 0)
        }
        var options: [MiningOption] = []
        if let cpu, cpu.engine.devices == [.cpu] { options.append(cpu) }
        if let gpu, gpu.engine.devices == [.gpu] { options.append(gpu) }
        return MiningPlan(options: options, netUSDPerDay: 0)
    }

    private func desiredPlan() -> MiningPlan {
        if let benchmarkOption { return MiningPlan(options: [benchmarkOption], netUSDPerDay: 0) }
        let s = settings
        switch s.switchingMode {
        case .manual:
            recommendedPlan = nil
            return manualPlan()
        case .recommend:
            let current = manualPlan()
            recommendedPlan = betterPlan(than: current)
            return current
        case .auto:
            guard !profit.markets.isEmpty, profit.btcUSD != nil else { return activePlan.options.isEmpty ? manualPlan() : activePlan }
            let rankedNow = ranked
            let skipLosses = s.pauseUnprofitable
            let best = ProfitPlanner.bestPlan(rankedNow, skipUnprofitable: skipLosses)
            unprofitableDevices = skipLosses ? ProfitPlanner.losingDevices(rankedNow) : []
            // A running coin that now loses money is dropped straight away – no margin or minimum run time.
            let currentEligible = !activePlan.options.isEmpty && activePlan.options.allSatisfy { o in
                guard let row = rankedNow.first(where: { $0.option == o }), row.isEligible else { return false }
                return !skipLosses || row.netUSDPerDay > 0
            }
            guard currentEligible else {
                if best.options != activePlan.options {
                    log(best.options.isEmpty ? "Paused – every ready coin loses money after electricity"
                                             : "Mining \(best.summary) – best profitable option")
                }
                recommendedPlan = nil
                if best.options.isEmpty { return skipLosses ? .empty : manualPlan() }
                return best
            }
            let currentNet = ProfitPlanner.value(of: activePlan.options, in: rankedNow)
            let better = ProfitPlanner.shouldSwitch(currentNet: currentNet, bestNet: best.netUSDPerDay, marginPercent: s.switchMarginPercent)
            recommendedPlan = better ? best : nil
            let checkDue = lastSwitchCheck.map { Date().timeIntervalSince($0) >= Double(max(1, s.switchCheckMinutes) * 60) } ?? true
            let ranLongEnough = planStartedAt.map { Date().timeIntervalSince($0) >= Double(max(0, s.minimumRunMinutes) * 60) } ?? true
            guard checkDue else { return activePlan }
            lastSwitchCheck = Date()
            if better && ranLongEnough && wantsMining {
                log(String(format: "Switched to %@ – %@/day vs %@/day", best.summary,
                           Format.usd(best.netUSDPerDay), Format.usd(currentNet)))
                recommendedPlan = nil
                return best
            }
            return activePlan
        }
    }

    private func betterPlan(than current: MiningPlan) -> MiningPlan? {
        guard !profit.markets.isEmpty else { return nil }
        let rankedNow = ranked
        let best = ProfitPlanner.bestPlan(rankedNow, skipUnprofitable: settings.pauseUnprofitable)
        guard !best.options.isEmpty, best.options != current.options else { return nil }
        let currentNet = ProfitPlanner.value(of: current.options, in: rankedNow)
        return ProfitPlanner.shouldSwitch(currentNet: currentNet, bestNet: best.netUSDPerDay,
                                          marginPercent: settings.switchMarginPercent) ? best : nil
    }

    private func setActive(_ plan: MiningPlan, reason: String?) {
        activePlan = plan
        planStartedAt = Date()
        if let reason { log(reason) }
    }

    private func log(_ message: String) {
        let stamp = Date().formatted(date: .omitted, time: .shortened)
        switchLog.insert("\(stamp)  \(message)", at: 0)
        if switchLog.count > 50 { switchLog.removeLast(switchLog.count - 50) }
    }

    private func updateBlockReasons() {
        let s = settings
        var reasons: [Device: String] = [:]
        for device in Device.allCases {
            let enabled = device == .cpu ? s.cpuEnabled : s.gpuEnabled
            if !enabled { reasons[device] = "\(device.label) mining is off in Settings"; continue }
            if let option = activePlan.option(on: device), let problem = s.readinessProblem(option) {
                reasons[device] = "\(option.coinTag): \(problem)"; continue
            }
            if let option = activePlan.option(on: device),
               !FileManager.default.isExecutableFile(atPath: option.engine.executable.path) {
                reasons[device] = "\(option.engine.displayName) isn't installed – rebuild with scripts/build-app.sh"; continue
            }
            if activePlan.option(on: device) == nil {
                reasons[device] = unprofitableDevices.contains(device) && s.switchingMode == .auto
                    ? "Paused – every coin loses money on the \(device.label) at \(Format.usd(s.electricityUSDPerKWh))/kWh"
                    : "No coin ready for the \(device.label)"
                continue
            }
            guard wantsMining, benchmarkOption == nil else { continue }
            if s.pauseOnBattery && system.onBattery { reasons[device] = "Paused – running on battery" }
            else if s.pauseOnThermalPressure && (system.thermalState == .serious || system.thermalState == .critical) {
                reasons[device] = "Paused – thermal pressure \(system.thermalLabel.lowercased())"
            } else if s.idleOnly && system.idleSeconds < Double(max(1, s.idleMinutes) * 60) {
                reasons[device] = "Waiting – mines after \(s.idleMinutes) min idle"
            }
        }
        blockReasons = reasons
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

    /// Engines that have been mining steadily for 5+ minutes teach the profit check their real hashrate.
    /// Only learns from an engine that is mining ALONE: with CPU and GPU mining together they share power and
    /// memory bandwidth (on an M5 Max XMRig drops from ~8.9 to ~3–4 kH/s), and those slowed numbers must not
    /// replace the solo benchmark the profit check relies on.
    private func recordLiveBenchmarks() {
        guard benchmarkOption == nil, engines.filter(\.isMining).count == 1 else { return }
        let watts = allocatedWatts
        for e in engines {
            guard e.isMining, e.totalHashrate > 0, let job = e.job, let started = e.process.startedAt,
                  Date().timeIntervalSince(started) > 300 else { continue }
            if let last = lastLiveRecord[job.option.engineAlgo], Date().timeIntervalSince(last) < 600 { continue }
            lastLiveRecord[job.option.engineAlgo] = Date()
            let measuredWatts: Double? = settings.powerSource == .manual || system.idleBaselineWatts == nil ? nil : watts[e.kind]
            let cpuF = settings.cpuPowerFactor, gpuF = settings.gpuPowerFactor
            benchmarks.record(BenchmarkResult(cpuHashrate: e.hashrate(for: .cpu) / cpuF, gpuHashrate: e.hashrate(for: .gpu) / gpuF,
                                              watts: measuredWatts.map { $0 / max(0.1, scaledWatts(1, kind: e.kind, cpu: cpuF, gpu: gpuF)) },
                                              date: Date(), coinTag: job.option.coinTag,
                                              fromLiveMining: true), for: job.option.engineAlgo)
        }
    }

    /// Feeds the Power vs Earnings chart (every 30 s, including idle periods so gaps show as zero).
    private func recordHistory() {
        let e = earnings
        history.record(EarningsSample(date: Date(), watts: e.totalWatts,
                                      grossPerDay: e.gross(.day), netPerDay: isMining ? e.net(.day) : 0,
                                      cpuHashrate: runningEngine(on: .cpu)?.hashrate(for: .cpu) ?? 0,
                                      gpuHashrate: runningEngine(on: .gpu)?.hashrate(for: .gpu) ?? 0))
    }

    // MARK: - Benchmark

    /// Runs each installed engine on its best ready coin, one at a time, measuring hashrate and power.
    func runBenchmark() {
        guard benchmarkTask == nil else { return }
        let rankedNow = ranked
        var queue: [MiningOption] = []
        // One run per engine + algorithm pair (e.g. XMRig on RandomX and on GhostRider), using its best ready coin.
        for pair in EngineAlgo.all where FileManager.default.isExecutableFile(atPath: pair.engine.executable.path) {
            if let best = rankedNow.first(where: { $0.option.engineAlgo == pair && settings.readinessProblem($0.option) == nil }) {
                queue.append(best.option)
            }
        }
        guard !queue.isEmpty else {
            benchmarkStatus = "Nothing to benchmark – add a wallet or Kryptex account for at least one coin"
            return
        }
        let resume = wantsMining
        benchmarkTask = Task { [weak self] in
            guard let self else { return }
            for (index, option) in queue.enumerated() {
                if Task.isCancelled { break }
                self.benchmarkProgress = Double(index) / Double(queue.count)
                await self.benchmark(option, step: index + 1, of: queue.count)
            }
            self.benchmarkOption = nil
            self.benchmarkProgress = nil
            self.benchmarkStatus = Task.isCancelled ? "Benchmark cancelled" : "Benchmark finished – profit check updated"
            self.benchmarkTask = nil
            self.wantsMining = resume
            self.lastSwitchCheck = nil   // re-plan right away with the new numbers
            self.evaluate()
        }
    }

    func cancelBenchmark() { benchmarkTask?.cancel() }

    private func benchmark(_ option: MiningOption, step: Int, of total: Int) async {
        let kind = option.engine
        let label = "\(step)/\(total) \(kind.displayName) on \(option.coinTag)"
        benchmarkOption = option
        evaluate()
        let e = engine(kind)
        // Warm-up: RandomX dataset or DAG generation.
        let timeout: TimeInterval = kind == .useleth ? 900 : (kind == .xmrig ? 120 : 300)
        let warmStart = Date()
        while !Task.isCancelled, e.totalHashrate <= 0, Date().timeIntervalSince(warmStart) < timeout {
            benchmarkStatus = "\(label): warming up (\(Int(Date().timeIntervalSince(warmStart)))s)…"
            try? await Task.sleep(for: .seconds(3))
        }
        guard !Task.isCancelled, e.totalHashrate > 0 else {
            benchmarkStatus = "\(label): no hashrate after \(Int(timeout))s – skipped"
            e.stop()
            return
        }
        var cpu: [Double] = [], gpu: [Double] = [], watts: [Double] = []
        let sampleStart = Date()
        while !Task.isCancelled, Date().timeIntervalSince(sampleStart) < 75 {
            try? await Task.sleep(for: .seconds(5))
            cpu.append(e.hashrate(for: .cpu)); gpu.append(e.hashrate(for: .gpu))
            if let now = system.systemWatts, let idle = system.idleBaselineWatts { watts.append(max(0, now - idle)) }
            benchmarkStatus = "\(label): measuring \(Format.hashrate(e.totalHashrate))"
        }
        guard !Task.isCancelled else { e.stop(); return }
        let avg: ([Double]) -> Double = { $0.isEmpty ? 0 : $0.reduce(0, +) / Double($0.count) }
        // Drop the first third: hashrate is still settling right after warm-up.
        let settle: ([Double]) -> [Double] = { Array($0.dropFirst($0.count / 3)) }
        let cpuF = settings.cpuPowerFactor, gpuF = settings.gpuPowerFactor
        benchmarks.record(BenchmarkResult(cpuHashrate: avg(settle(cpu)) / cpuF, gpuHashrate: avg(settle(gpu)) / gpuF,
                                          watts: watts.isEmpty ? nil : avg(settle(watts)) / max(0.1, scaledWatts(1, kind: kind, cpu: cpuF, gpu: gpuF)),
                                          date: Date(), coinTag: option.coinTag, fromLiveMining: false), for: option.engineAlgo)
        e.stop()
        try? await Task.sleep(for: .seconds(5)) // let power settle before the next engine
    }

    // MARK: - Earnings

    /// Measured (or estimated) watts charged to each running engine.
    var allocatedWatts: [EngineKind: Double] {
        let s = settings
        var estimates: [EngineKind: Double] = [:]
        for e in engines where e.isMining { estimates[e.kind] = ProfitPlanner.wattsEstimate(e.kind, settings: s) }
        let total = estimates.values.reduce(0, +)
        guard total > 0 else { return [:] }
        switch s.powerSource {
        case .manual:
            return estimates
        case .measuredTotal, .measuredIncremental:
            guard let measured = system.systemWatts else { return estimates }
            var watts = measured
            if s.powerSource == .measuredIncremental {
                guard let baseline = system.idleBaselineWatts else { return estimates }
                watts = max(0, measured - baseline)
            }
            return estimates.mapValues { watts * $0 / total }
        }
    }

    /// Two-word version for the dashboard tile.
    var powerSourceShort: String {
        switch settings.powerSource {
        case .manual: return "Estimated"
        case .measuredTotal: return system.systemWatts == nil ? "Estimated" : "Whole Mac"
        case .measuredIncremental:
            return system.systemWatts == nil || system.idleBaselineWatts == nil ? "Estimated" : "Measured above idle"
        }
    }

    var powerSourceDescription: String {
        switch settings.powerSource {
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
        var rows: [CoinEarnings] = []
        for e in engines {
            guard e.isMining, let job = e.job, let coin = job.option.coin else { continue }
            let hashrate = e.totalHashrate
            let keep = (1 - job.poolFeePercent / 100) * (1 - e.kind.devFeePercent / 100)
            var row = CoinEarnings(tag: coin.tag, name: coin.name, algorithm: coin.algorithm, engine: e.kind,
                                   hashrate: hashrate, coinsPerSecond: 0, priceUSD: nil, watts: watts[e.kind] ?? 0,
                                   networkHashrate: nil, blockReward: nil, dataSource: nil)
            if let m = profit.market(for: coin), let btc = profit.btcUSD {
                row.coinsPerSecond = m.coinsPerSecond(hashrate: hashrate, useDayAverages: false) * keep
                row.priceUSD = m.priceUSD(btcUSD: btc, useDayAverages: false)
                row.networkHashrate = m.networkHashrate
                row.blockReward = m.blockReward
                row.dataSource = "WhatToMine + CoinGecko"
            } else if let legacy = Coin(rawValue: coin.tag.lowercased()), let net = market.network[legacy] {
                row.coinsPerSecond = EarningsCalculator.coinsPerSecond(coin: legacy, hashrate: hashrate, network: net,
                                                                      poolFeePercent: job.poolFeePercent,
                                                                      devFeePercent: e.kind.devFeePercent)
                row.priceUSD = market.prices[legacy]
                row.networkHashrate = net.networkHashrate(for: legacy)
                row.blockReward = net.blockReward
                row.dataSource = net.source
            }
            rows.append(row)
        }
        return EarningsSnapshot(coins: rows, electricityUSDPerKWh: s.electricityUSDPerKWh,
                                totalWatts: watts.values.reduce(0, +))
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

    /// 0x + 40 hex characters (ETHW, Quai, Etica, …).
    static func isHex40(_ address: String) -> Bool {
        let a = address.trimmingCharacters(in: .whitespaces)
        return a.count == 42 && a.hasPrefix("0x") && a.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    /// nil = no opinion (format not checked for this coin).
    static func check(tag: String, address: String) -> Bool? {
        guard !address.isEmpty else { return nil }
        switch tag {
        case "XMR": return isMonero(address)
        case "RVN": return isRavencoin(address)
        case "ETHW", "QUAI", "ETI", "OCTA", "QKC": return isHex40(address)
        default: return address.contains(" ") ? false : nil
        }
    }
}
