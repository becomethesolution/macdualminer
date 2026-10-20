import Foundation
import Observation

/// One point on the Power vs Earnings chart.
struct EarningsSample: Codable, Equatable, Identifiable {
    var date: Date
    var watts: Double
    var grossPerDay: Double
    var netPerDay: Double
    var cpuHashrate: Double
    var gpuHashrate: Double
    var id: Date { date }
}

/// Rolling 24-hour history of power draw and earnings, sampled every 30 s and kept across launches.
@MainActor
@Observable
final class EarningsHistory {
    private(set) var samples: [EarningsSample] = []

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var lastSample: Date?
    @ObservationIgnored private var lastSave: Date?
    @ObservationIgnored let interval: TimeInterval
    @ObservationIgnored let retention: TimeInterval

    init(url: URL = AppPaths.supportDirectory.appendingPathComponent("history.json"),
         interval: TimeInterval = 30, retention: TimeInterval = 24 * 3600) {
        self.url = url
        self.interval = interval
        self.retention = retention
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let saved = try? decoder.decode([EarningsSample].self, from: data) {
            samples = saved.filter { Date().timeIntervalSince($0.date) < retention }
        }
    }

    /// Adds a sample if `interval` has passed. Call often; it rate-limits itself.
    func record(_ sample: EarningsSample, force: Bool = false) {
        if !force, let last = lastSample, sample.date.timeIntervalSince(last) < interval { return }
        lastSample = sample.date
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-retention)
        if let first = samples.firstIndex(where: { $0.date >= cutoff }), first > 0 { samples.removeFirst(first) }
        if lastSave.map({ sample.date.timeIntervalSince($0) > 300 }) ?? true { save(); lastSave = sample.date }
    }

    func samples(lastHours hours: Double, now: Date = Date()) -> [EarningsSample] {
        let cutoff = now.addingTimeInterval(-hours * 3600)
        return samples.filter { $0.date >= cutoff }
    }

    /// Average net and gross USD/day and watts over a window (only counting samples while mining).
    func averages(lastHours hours: Double) -> (net: Double, gross: Double, watts: Double)? {
        let mining = samples(lastHours: hours).filter { $0.watts > 0 || $0.grossPerDay > 0 }
        guard !mining.isEmpty else { return nil }
        let n = Double(mining.count)
        return (mining.map(\.netPerDay).reduce(0, +) / n,
                mining.map(\.grossPerDay).reduce(0, +) / n,
                mining.map(\.watts).reduce(0, +) / n)
    }

    func clear() { samples.removeAll(); save() }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(samples) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
