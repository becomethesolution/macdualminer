import Foundation
import Observation

/// GPU mining: Ethash coins (EthereumPoW, …) through ethminer-m1, an OpenCL build for Apple Silicon.
@MainActor
@Observable
final class EthminerController: MiningEngine {
    let kind = EngineKind.ethminer
    let process = MinerProcess(name: "ethminer-m1 (GPU · Ethash)")
    private(set) var job: MiningJob?
    private(set) var activeSignature: String?
    private(set) var acceptedShares = 0
    private(set) var rejectedShares = 0
    private(set) var phase = "Idle"
    private(set) var epoch: Int?
    private(set) var meter = HashrateMeter()

    init() {
        process.onLine = { [weak self] line in self?.parse(line) }
    }

    var isMining: Bool { process.isRunning }
    var statusText: String { process.isRunning ? phase : process.state.label }
    var displayHashrate: Double? { meter.latest }

    func hashrate(for device: Device) -> Double {
        guard device == .gpu, isMining else { return 0 }
        return meter.effective
    }

    func start(job: MiningJob, settings: MinerSettings, hardware: HardwareInfo) {
        stop()
        self.job = job
        activeSignature = job.signature
        phase = "Connecting to pool…"
        process.start(
            executable: AppPaths.ethminerExecutable,
            arguments: ["-G", "-P", Self.poolURL(for: job), "--HWMON", "0", "--display-interval", "10", "--nocolor"],
            workingDirectory: AppPaths.cacheDirectory
        )
    }

    func stop() {
        process.stop()
        job = nil
        activeSignature = nil
        acceptedShares = 0; rejectedShares = 0
        meter.reset()
        epoch = nil
        phase = "Idle"
    }

    /// ethminer reads the login from the URL's user part; anything other than the "." worker
    /// separator (e.g. Kryptex's "wallet/worker") must be percent-encoded.
    nonisolated static func poolURL(for job: MiningJob) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "._-~")
        let user = job.login.addingPercentEncoding(withAllowedCharacters: allowed) ?? job.login
        let pass = job.password.addingPercentEncoding(withAllowedCharacters: allowed) ?? "x"
        let scheme = job.tls ? "stratums" : "stratum"
        return "\(scheme)://\(user):\(pass)@\(job.poolAddress)"
    }

    func parse(_ line: String) {
        // "m 22:06:20 0:00 A12:R1 41.56 Mh - cl0 41.56"
        if let m = HashUnit.firstMatch(#"\bA(\d+)(?::R(\d+))?(?:\+\d+)?(?::F\d+)?\s+([0-9.]+)\s*(h|Kh|Mh|Gh)\b"#, in: line),
           let hs = HashUnit.value(m[3], unit: m[4]) {
            acceptedShares = Int(m[1]) ?? acceptedShares
            rejectedShares = Int(m[2]) ?? rejectedShares
            if hs > 0 {
                meter.record(hs)
                phase = "Mining"
            }
            return
        }
        if let m = HashUnit.firstMatch(#"Epoch\s*:\s*(\d+)"#, in: line) { epoch = Int(m[1]) }
        if line.contains("Generating split DAG") || line.contains("Creating DAG buffer") { phase = "Generating DAG on GPU…" }
        else if line.contains("DAG data generated") { phase = "DAG ready – starting" }
        else if line.contains("Established connection") { phase = "Connected – waiting for work" }
        else if line.contains("Authorized worker") { phase = "Authorized – waiting for work" }
        else if line.localizedCaseInsensitiveContains("unauthorized") || line.contains("Worker not authorized") {
            phase = "Pool rejected the login – check the wallet"
        }
        else if line.contains("No connection") || line.contains("Disconnected") { phase = "Disconnected from pool" }
    }
}
