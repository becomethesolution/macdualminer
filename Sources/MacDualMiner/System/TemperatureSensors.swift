import Foundation
import IOKit

/// Reads Apple Silicon temperature sensors through IOKit's HID event system, the same source
/// Activity-Monitor-style tools use. No root needed. The functions aren't in the public headers,
/// so they're looked up at runtime; if any is missing the reader simply reports nothing.
final class TemperatureSensors {
    struct Reading {
        /// Hottest chip (die / SoC) sensor, °C.
        var chipC: Double?
        /// Battery temperature on laptops, °C.
        var batteryC: Double?
        /// Number of chip sensors the hottest value was taken from.
        var chipSensorCount: Int
    }

    private typealias CreateFn = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias SetMatchingFn = @convention(c) (OpaquePointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (OpaquePointer, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (OpaquePointer, Int64, Int32, Int64) -> OpaquePointer?
    private typealias GetFloatFn = @convention(c) (OpaquePointer, Int32) -> Double

    private static let temperatureEventType: Int64 = 15                 // kIOHIDEventTypeTemperature
    private static let temperatureField: Int32 = Int32(15 << 16)        // IOHIDEventFieldBase(type)

    private let copyServices: CopyServicesFn
    private let copyProperty: CopyPropertyFn
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let client: OpaquePointer

    init?() {
        guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(iokit, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(iokit, "IOHIDEventSystemClientSetMatching"),
              let services = dlsym(iokit, "IOHIDEventSystemClientCopyServices"),
              let property = dlsym(iokit, "IOHIDServiceClientCopyProperty"),
              let event = dlsym(iokit, "IOHIDServiceClientCopyEvent"),
              let float = dlsym(iokit, "IOHIDEventGetFloatValue")
        else { return nil }
        copyServices = unsafeBitCast(services, to: CopyServicesFn.self)
        copyProperty = unsafeBitCast(property, to: CopyPropertyFn.self)
        copyEvent = unsafeBitCast(event, to: CopyEventFn.self)
        getFloat = unsafeBitCast(float, to: GetFloatFn.self)
        guard let client = unsafeBitCast(create, to: CreateFn.self)(kCFAllocatorDefault) else { return nil }
        self.client = client
        // Apple vendor usage page 0xFF00, usage 5 = temperature sensors.
        let matching = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary
        _ = unsafeBitCast(setMatching, to: SetMatchingFn.self)(client, matching)
    }

    func read() -> Reading {
        var chip: [Double] = []
        var other: [Double] = []
        var battery: Double?
        guard let array = copyServices(client)?.takeRetainedValue() else { return Reading(chipC: nil, batteryC: nil, chipSensorCount: 0) }
        for index in 0..<CFArrayGetCount(array) {
            guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
            let service = OpaquePointer(raw)
            let name = (copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
            guard let event = copyEvent(service, Self.temperatureEventType, 0, 0) else { continue }
            let celsius = getFloat(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release()
            guard celsius > 5, celsius < 130 else { continue }
            let lower = name.lowercased()
            if lower.contains("battery") || lower.contains("gas gauge") {
                battery = max(battery ?? 0, celsius)
            } else if lower.contains("tdie") || lower.contains("soc") || lower.contains("cpu") || lower.contains("gpu")
                        || lower.hasPrefix("pmu tp") || lower.contains("pacc") || lower.contains("eacc") {
                chip.append(celsius)
            } else if !lower.contains("nand") && !lower.contains("ssd") {
                other.append(celsius)
            }
        }
        // Newer chips may name their sensors differently; fall back to the hottest non-storage sensor.
        let pool = chip.isEmpty ? other : chip
        return Reading(chipC: pool.max(), batteryC: battery, chipSensorCount: pool.count)
    }
}

/// How temperatures are shown.
enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }

    var label: String { self == .fahrenheit ? "°F" : "°C" }

    /// °F for US-style locales, °C everywhere else.
    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    func format(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        let value = self == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded())) \(label)"
    }
}
