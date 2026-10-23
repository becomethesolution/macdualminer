import Foundation
import Observation
import IOKit.ps
import CoreGraphics

/// Power draw, battery, thermal pressure and user-idle time.
@MainActor
@Observable
final class SystemMonitor {
    /// Whole-Mac power in watts from the SMC, smoothed. nil if the sensor isn't readable.
    private(set) var systemWatts: Double?
    /// Typical power while *not* mining, learnt automatically. Used for "extra power over idle".
    private(set) var idleBaselineWatts: Double?
    private(set) var onBattery = false
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var idleSeconds: Double = 0
    /// Hottest chip sensor in °C, nil if this Mac's sensors can't be read.
    private(set) var chipTemperatureC: Double?
    /// Battery temperature in °C (laptops).
    private(set) var batteryTemperatureC: Double?
    private(set) var chipSensorCount = 0

    @ObservationIgnored private let smc = SMCReader()
    @ObservationIgnored private let temperatures = TemperatureSensors()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var notMiningSince: Date? = Date()

    var powerSensorAvailable: Bool { smc != nil && systemWatts != nil }

    var thermalLabel: String {
        switch thermalState {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    func start(isMining: @escaping @MainActor () -> Bool) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample(mining: isMining())
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func sample(mining: Bool) {
        thermalState = ProcessInfo.processInfo.thermalState
        onBattery = Self.isOnBatteryPower()
        idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if let reading = temperatures?.read() {
            chipTemperatureC = reading.chipC.map { new in chipTemperatureC.map { $0 * 0.5 + new * 0.5 } ?? new }
            batteryTemperatureC = reading.batteryC
            chipSensorCount = reading.chipSensorCount
        }

        if let raw = smc?.readFloat("PSTR"), raw > 0, raw < 1000 {
            systemWatts = systemWatts.map { $0 * 0.7 + raw * 0.3 } ?? raw

            if mining {
                notMiningSince = nil
            } else {
                if notMiningSince == nil { notMiningSince = Date() }
                // Skip the first 20s after mining stops so the baseline isn't polluted by spin-down.
                if let since = notMiningSince, Date().timeIntervalSince(since) > 20 {
                    idleBaselineWatts = idleBaselineWatts.map { $0 * 0.95 + raw * 0.05 } ?? raw
                }
            }
        }
    }

    nonisolated static func isOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}
