import Foundation
import Observation

/// CPU + GPU mining of Ethash (EthereumPoW) with UselethMiner: ARMv8 assembly on the CPU and Metal on the GPU,
/// both in one process. Closed-source, 1% dev fee, no TLS.
@MainActor
@Observable
final class UselethController: MiningEngine {
    let kind = EngineKind.useleth
    let process = MinerProcess(name: "UselethMiner (CPU + GPU · Ethash)")
    private(set) var job: MiningJob?
    private(set) var activeSignature: String?
    private(set) var acceptedShares = 0
    private(set) var rejectedShares = 0
    private(set) var phase = "Idle"
    private(set) var cpuMeter = HashrateMeter()
    private(set) var gpuMeter = HashrateMeter()

    init() {
        process.onLine = { [weak self] line in self?.parse(line) }
    }

    var isMining: Bool { process.isRunning }
    var statusText: String { process.isRunning ? phase : process.state.label }
    var displayHashrate: Double? {
        guard cpuMeter.latest != nil || gpuMeter.latest != nil else { return nil }
        return (cpuMeter.latest ?? 0) + (gpuMeter.latest ?? 0)
    }

    func hashrate(for device: Device) -> Double {
        guard isMining else { return 0 }
        return device == .cpu ? cpuMeter.effective : gpuMeter.effective
    }

    func start(job: MiningJob, settings: MinerSettings, hardware: HardwareInfo) {
        stop()
        self.job = job
        activeSignature = job.signature + "|" + settings.cpuTuningSignature
        phase = "Loading DAG (first run can take a few minutes)…"
        let threads = settings.uselethThreads > 0 ? settings.uselethThreads : settings.cpuThreads(totalCores: hardware.totalCores)
        process.start(
            executable: AppPaths.uselethExecutable,
            arguments: Self.arguments(for: job, threads: threads),
            workingDirectory: AppPaths.uselethDirectory,
            pseudoTerminal: true   // otherwise it prints in ~1-minute bursts and the stats lag
        )
    }

    nonisolated static func arguments(for job: MiningJob, threads: Int) -> [String] {
        ["\(job.login)@\(job.poolAddress)",
         "-t", String(max(1, threads)),
         "--flavor", "armv8af", "--size", "64",
         "--flavor-gpu", "metal", "--size-gpu", "128"]
    }

    func stop() {
        process.stop()
        job = nil
        activeSignature = nil
        acceptedShares = 0; rejectedShares = 0
        cpuMeter.reset(); gpuMeter.reset()
        phase = "Idle"
    }

    func parse(_ line: String) {
        // "[STATUS] CPU[ 7436837 h/s :: 1155 s/a :: … ] GPU[ 31982661 h/s :: 268 s/a :: … ]"
        if line.contains("[STATUS]") {
            if let m = HashUnit.firstMatch(#"CPU\[\s*([0-9.]+)\s*h/s"#, in: line), let v = Double(m[1]) {
                if v > 0 { cpuMeter.record(v) }
            }
            if let m = HashUnit.firstMatch(#"GPU\[\s*([0-9.]+)\s*h/s"#, in: line), let v = Double(m[1]) {
                if v > 0 { gpuMeter.record(v) }
            }
            if (cpuMeter.latest ?? 0) + (gpuMeter.latest ?? 0) > 0 { phase = "Mining" }
            return
        }
        let lower = line.lowercased()
        // UselethMiner never logs the pool's verdict – only "[SUBMIT] epoch:… hash:… nonce:…" when it sends a
        // share – so its share count is shares submitted. Its own submit errors count as rejected.
        if line.contains("[SUBMIT] epoch:") { acceptedShares += 1 }
        else if line.contains("[SUBMIT]") && (line.contains("DIFFICULTY ERROR") || line.contains("JOB NOT FOUND")
                    || line.contains("does not exist") || line.contains("does not match job")) {
            // A failed submit was already counted when it was sent – move it from submitted to rejected.
            rejectedShares += 1
            if acceptedShares > 0 { acceptedShares -= 1 }
        }
        else if line.contains("Loading DAG") { phase = "Loading DAG…" }
        else if line.contains("Loaded DAG") { phase = "DAG loaded – starting threads" }
        else if line.contains("[SUBSCRIBE]") || line.contains("Connected") { phase = "Connected to pool" }
        else if lower.contains("illegal instruction") { phase = "CPU backend crashed – try fewer threads" }
    }
}
