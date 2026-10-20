import Foundation
import Observation

/// GPU mining: Ravencoin (KawPow) through kawpow-metal, a native Metal miner.
/// It has no API, so stats are parsed from its output.
@MainActor
@Observable
final class KawpowController: MiningEngine {
    let kind = EngineKind.kawpow
    let process = MinerProcess(name: "kawpow-metal (GPU · KawPow)")
    private(set) var job: MiningJob?

    private(set) var hashrate: Double?          // H/s, latest reading
    private(set) var averageHashrate: Double?   // H/s, smoothed
    private(set) var acceptedShares = 0
    private(set) var rejectedShares = 0
    private(set) var phase = "Idle"
    private(set) var blockHeight: Int?
    private(set) var lastHashrateAt: Date?
    private(set) var activeSignature: String?

    init() {
        process.onLine = { [weak self] line in self?.parse(line) }
    }

    var isMining: Bool { process.isRunning }

    var effectiveHashrate: Double {
        guard isMining, let last = lastHashrateAt, Date().timeIntervalSince(last) < 120 else { return 0 }
        return averageHashrate ?? hashrate ?? 0
    }

    var statusText: String { process.isRunning ? phase : process.state.label }
    var displayHashrate: Double? { hashrate }

    func hashrate(for device: Device) -> Double { device == .gpu ? effectiveHashrate : 0 }

    func start(job: MiningJob, settings: MinerSettings, hardware: HardwareInfo) {
        stop()
        activeSignature = job.signature
        self.job = job
        phase = "Connecting to pool…"
        process.start(
            executable: AppPaths.kawpowExecutable,
            arguments: ["--pool", job.poolAddress, "--worker", job.login],
            environment: [
                "KAWPOW_RESOURCE_DIR": AppPaths.kawpowDirectory.path,
                "KAWPOW_CACHE_DIR": AppPaths.kawpowCacheDirectory.path,
            ],
            workingDirectory: AppPaths.kawpowCacheDirectory
        )
    }

    func stop() {
        process.stop()
        activeSignature = nil
        job = nil
        hashrate = nil; averageHashrate = nil; lastHashrateAt = nil
        acceptedShares = 0; rejectedShares = 0
        blockHeight = nil
        phase = "Idle"
    }

    // MARK: - Output parsing

    func parse(_ line: String) {
        if let mh = Self.parseMegahash(line) {
            // The first reading after each new job is timed over a single tiny batch and is wildly high
            // ("16169.29 MH/s | 65536 hashes"); skip it so it can't inflate the average or a benchmark.
            guard Self.isSettledSample(line) else { return }
            let hs = mh * 1_000_000
            hashrate = hs
            averageHashrate = averageHashrate.map { $0 * 0.8 + hs * 0.2 } ?? hs
            lastHashrateAt = Date()
            phase = "Mining"
            return
        }
        if line.contains("Share accepted") { acceptedShares += 1; return }
        if line.contains("Share rejected") { rejectedShares += 1; return }
        if line.contains("Connecting to pool") { phase = "Connecting to pool…" }
        else if line.contains("Waiting for first job") { phase = "Waiting for first job…" }
        else if line.contains("light cache") || line.contains("Building cache") || line.contains("RandMemoHash") { phase = "Building light cache…" }
        else if line.contains("Generating DAG") { phase = "Generating DAG on GPU…" }
        else if let pct = Self.parseProgress(line) { phase = String(format: "Generating DAG… %.0f%%", pct) }
        else if line.contains("Compiling") { phase = "Compiling Metal kernel…" }
        else if line.contains("MINING block") { phase = "Mining" }
        else if line.contains("Auth failed") { phase = "Pool rejected the worker – check your RVN address" }
        else if line.contains("Disconnected") || line.contains("Connection closed") { phase = "Disconnected from pool" }

        if let height = Self.parseHeight(line) { blockHeight = height }
    }

    /// "  6.31 MH/s | 123456 hashes | 0.1h" → 6.31
    nonisolated static func parseMegahash(_ line: String) -> Double? {
        guard let range = line.range(of: #"([0-9]+(?:\.[0-9]+)?)\s*MH/s"#, options: .regularExpression) else { return nil }
        let token = line[range].replacingOccurrences(of: "MH/s", with: "").trimmingCharacters(in: .whitespaces)
        return Double(token)
    }

    /// False for the first batch of a job: "16169.29 MH/s | 65536 hashes | 0.0h".
    nonisolated static func isSettledSample(_ line: String) -> Bool {
        guard let range = line.range(of: #"\|\s*([0-9]+)\s+hashes"#, options: .regularExpression) else { return true }
        let hashes = Int(line[range].filter(\.isNumber)) ?? 0
        return hashes > 1_000_000
    }

    /// "  [#####-----]  45.0% (12s)" → 45.0
    nonisolated static func parseProgress(_ line: String) -> Double? {
        guard line.contains("["), let range = line.range(of: #"([0-9]+(?:\.[0-9]+)?)%"#, options: .regularExpression) else { return nil }
        return Double(line[range].dropLast())
    }

    /// "Height: 4588318, Epoch: 611" or "MINING block 4588318"
    nonisolated static func parseHeight(_ line: String) -> Int? {
        for pattern in [#"Height: ([0-9]+)"#, #"block ([0-9]+)"#] {
            if let range = line.range(of: pattern, options: .regularExpression) {
                let digits = line[range].filter(\.isNumber)
                if let value = Int(digits) { return value }
            }
        }
        return nil
    }
}
