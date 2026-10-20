import Foundation

/// Common surface of every bundled mining engine.
@MainActor
protocol MiningEngine: AnyObject {
    var kind: EngineKind { get }
    var process: MinerProcess { get }
    /// The job currently running (nil when stopped).
    var job: MiningJob? { get }
    var activeSignature: String? { get }
    var isMining: Bool { get }
    var acceptedShares: Int { get }
    var rejectedShares: Int { get }
    /// One-line status for the dashboard.
    var statusText: String { get }
    /// Latest total hashrate reading, H/s.
    var displayHashrate: Double? { get }
    /// Smoothed hashrate this engine contributes on one part of the chip (0 if none).
    func hashrate(for device: Device) -> Double
    func start(job: MiningJob, settings: MinerSettings, hardware: HardwareInfo)
    func stop()
}

extension MiningEngine {
    var totalHashrate: Double { hashrate(for: .cpu) + hashrate(for: .gpu) }
}

/// Exponential smoothing that ignores readings older than `staleAfter`.
struct HashrateMeter: Equatable {
    private(set) var latest: Double?
    private(set) var average: Double?
    private(set) var updatedAt: Date?
    var staleAfter: TimeInterval = 120

    mutating func record(_ value: Double, weight: Double = 0.2) {
        guard value.isFinite, value >= 0 else { return }
        latest = value
        average = average.map { $0 * (1 - weight) + value * weight } ?? value
        updatedAt = Date()
    }

    mutating func reset() { latest = nil; average = nil; updatedAt = nil }

    var effective: Double {
        guard let updatedAt, Date().timeIntervalSince(updatedAt) < staleAfter else { return 0 }
        return average ?? latest ?? 0
    }
}

enum HashUnit {
    /// "41.56", "Mh" → 41_560_000
    static func value(_ number: String, unit: String) -> Double? {
        guard let n = Double(number) else { return nil }
        switch unit.lowercased().prefix(1) {
        case "k": return n * 1e3
        case "m": return n * 1e6
        case "g": return n * 1e9
        case "t": return n * 1e12
        default: return n
        }
    }

    static func firstMatch(_ pattern: String, in line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            let r = match.range(at: i)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: line) else { return "" }
            return String(line[swiftRange])
        }
    }
}
