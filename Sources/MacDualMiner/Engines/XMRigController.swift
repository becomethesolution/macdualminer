import Foundation
import Observation

/// CPU mining: Monero (RandomX) through XMRig. Stats come from XMRig's local HTTP API.
@MainActor
@Observable
final class XMRigController {
    let process = MinerProcess(name: "XMRig (CPU · Monero)")

    private(set) var hashrate10s: Double?
    private(set) var hashrate60s: Double?
    private(set) var hashrate15m: Double?
    private(set) var acceptedShares = 0
    private(set) var rejectedShares = 0
    private(set) var poolAddress: String?
    private(set) var poolPing: Int?
    private(set) var threadsInUse: Int?
    private(set) var lastStatsAt: Date?
    private(set) var statusNote: String?
    private(set) var activeSignature: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var apiPort = 0
    @ObservationIgnored private var apiToken = ""

    var isMining: Bool { process.isRunning }

    /// Best hashrate for earnings maths: 60s average, falling back to 10s.
    var effectiveHashrate: Double {
        guard isMining else { return 0 }
        return hashrate60s ?? hashrate10s ?? 0
    }

    func start(settings: MinerSettings, hardware: HardwareInfo) {
        stop()
        apiPort = Int.random(in: 42_000...42_999)
        apiToken = UUID().uuidString
        do {
            let config = Self.makeConfig(settings: settings, hardware: hardware, port: apiPort, token: apiToken)
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: AppPaths.xmrigConfigFile, options: .atomic)
        } catch {
            statusNote = "Couldn't write XMRig config: \(error.localizedDescription)"
            return
        }
        statusNote = "Starting… (RandomX dataset init takes ~10–30s)"
        activeSignature = settings.cpuConfigSignature
        process.start(
            executable: AppPaths.xmrigExecutable,
            arguments: ["--config", AppPaths.xmrigConfigFile.path, "--no-color"],
            workingDirectory: AppPaths.supportDirectory
        )
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        process.stop()
        activeSignature = nil
        hashrate10s = nil; hashrate60s = nil; hashrate15m = nil
        acceptedShares = 0; rejectedShares = 0
        poolAddress = nil; poolPing = nil; threadsInUse = nil; lastStatsAt = nil
        statusNote = nil
    }

    // MARK: - Config

    nonisolated static func makeConfig(settings s: MinerSettings, hardware: HardwareInfo, port: Int, token: String) -> [String: Any] {
        var cpu: [String: Any] = [
            "enabled": true,
            "huge-pages": false,          // not available on macOS
            "hw-aes": NSNull(),           // auto-detect (ARMv8 crypto extensions)
            "priority": max(0, min(5, s.cpuPriority)),
            "yield": s.cpuYield,
            "max-threads-hint": 100,
        ]
        if let threads = s.cpuPreset.threads(totalCores: hardware.totalCores, custom: s.cpuCustomThreads) {
            // One entry per thread; -1 = no affinity (macOS doesn't support pinning anyway).
            cpu["rx"] = Array(repeating: -1, count: threads)
        }

        let worker = s.workerName.isEmpty ? "mac" : s.workerName
        let pool: [String: Any] = [
            "url": s.xmrPool,
            "user": s.xmrWallet,
            "pass": worker,               // SupportXMR & most nodejs-pools use the password as worker name
            "rig-id": worker,
            "keepalive": true,
            "tls": s.xmrPoolTLS,
            "coin": "monero",
            "algo": "rx/0",
            "enabled": true,
        ]

        return [
            "autosave": false,
            "background": false,
            "colors": false,
            "title": false,
            "donate-level": max(1, Int(s.xmrDevFeePercent.rounded())),
            "donate-over-proxy": 1,
            "print-time": 30,
            "health-print-time": 0,
            "retries": 5,
            "retry-pause": 5,
            "syslog": false,
            "watch": false,
            "pause-on-battery": false,    // the app applies its own rules
            "pause-on-active": false,
            "http": [
                "enabled": true,
                "host": "127.0.0.1",
                "port": port,
                "access-token": token,
                "restricted": true,
            ] as [String: Any],
            "randomx": [
                "init": -1,
                "init-avx2": -1,
                "mode": "fast",           // 2 GB dataset; the M5 Max has plenty of memory
                "1gb-pages": false,
                "rdmsr": false,
                "wrmsr": false,
                "cache_qos": false,
                "numa": false,
                "scratchpad_prefetch_mode": 1,
            ] as [String: Any],
            "cpu": cpu,
            "opencl": false,
            "cuda": false,
            "pools": [pool],
        ]
    }

    // MARK: - API polling

    private func startPolling() {
        pollTask?.cancel()
        let port = apiPort, token = apiToken
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                let summary = await Self.fetchSummary(port: port, token: token)
                self?.apply(summary)
            }
        }
    }

    private func apply(_ summary: XMRigSummary?) {
        guard isMining else { return }
        guard let summary else {
            if lastStatsAt == nil { statusNote = "Waiting for XMRig API…" }
            return
        }
        let totals = summary.hashrate?.total ?? []
        hashrate10s = totals.count > 0 ? totals[0] : nil
        hashrate60s = totals.count > 1 ? totals[1] : nil
        hashrate15m = totals.count > 2 ? totals[2] : nil
        acceptedShares = summary.connection?.accepted ?? summary.results?.shares_good ?? 0
        rejectedShares = summary.connection?.rejected ?? 0
        poolAddress = summary.connection?.pool
        poolPing = summary.connection?.ping
        threadsInUse = summary.hashrate?.threads?.count
        lastStatsAt = Date()
        if hashrate10s == nil {
            statusNote = "Initialising RandomX dataset…"
        } else if (summary.connection?.uptime ?? 0) == 0 {
            statusNote = "Hashing, but not connected to the pool yet"
        } else {
            statusNote = nil
        }
    }

    nonisolated static func fetchSummary(port: Int, token: String) async -> XMRigSummary? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/2/summary") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let result = try? await URLSession.shared.data(for: request),
              case let (data, response) = result,
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(XMRigSummary.self, from: data)
    }
}

/// Subset of XMRig's /2/summary response.
struct XMRigSummary: Decodable {
    struct Hashrate: Decodable {
        let total: [Double?]?
        let threads: [[Double?]]?
    }
    struct Results: Decodable {
        let shares_good: Int?
        let shares_total: Int?
    }
    struct Connection: Decodable {
        let pool: String?
        let uptime: Int?
        let ping: Int?
        let accepted: Int?
        let rejected: Int?
    }
    let hashrate: Hashrate?
    let results: Results?
    let connection: Connection?

    private enum CodingKeys: String, CodingKey { case hashrate, results, connection }
}
