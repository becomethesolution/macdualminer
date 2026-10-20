import Foundation
import Metal
import IOKit
import SystemConfiguration

enum AppPaths {
    static let appName = "MacDualMiner"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent(appName, isDirectory: true))
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent(appName, isDirectory: true))
    }

    static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    static var xmrigConfigFile: URL { supportDirectory.appendingPathComponent("xmrig-config.json") }
    static var kawpowCacheDirectory: URL { ensure(cacheDirectory.appendingPathComponent("kawpow", isDirectory: true)) }

    /// Engines are bundled at MacDualMiner.app/Contents/Resources/engines/…
    static var enginesDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MACDUALMINER_ENGINES"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return (Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")).appendingPathComponent("engines", isDirectory: true)
    }

    static var xmrigExecutable: URL { enginesDirectory.appendingPathComponent("xmrig/xmrig") }
    static var kawpowDirectory: URL { enginesDirectory.appendingPathComponent("kawpow", isDirectory: true) }
    static var kawpowExecutable: URL { kawpowDirectory.appendingPathComponent("kawpow-metal") }
    static var ethminerExecutable: URL { enginesDirectory.appendingPathComponent("ethminer/ethminer-m1") }
    /// UselethMiner is closed-source freeware, so it isn't bundled: the app downloads it from the author's
    /// GitHub release on request and installs it here.
    static var uselethDirectory: URL { supportDirectory.appendingPathComponent("engines/useleth", isDirectory: true) }
    static var uselethExecutable: URL { uselethDirectory.appendingPathComponent("uselethminer") }
    static var benchmarksFile: URL { supportDirectory.appendingPathComponent("benchmarks.json") }

    @discardableResult
    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct HardwareInfo {
    let chipName: String
    let totalCores: Int
    let superCores: Int
    let performanceCores: Int
    let gpuName: String
    let memoryGB: Int
    /// "Ram's MacBook Pro" – the name set in System Settings › General › Sharing.
    var computerName: String = ""
    /// Marketing name, e.g. "MacBook Pro (16-inch, 2026)".
    var modelName: String = ""
    /// e.g. "Mac17,6".
    var modelIdentifier: String = ""
    var gpuCores: Int? = nil

    /// "MacBook Pro (16-inch, 2026) · Apple M5 Max · 18 CPU cores (6 + 12) · 40-core GPU · 128 GB"
    var detailLine: String {
        var parts: [String] = []
        let model = modelName.isEmpty ? modelIdentifier : modelName
        if !model.isEmpty { parts.append(modelIdentifier.isEmpty || model == modelIdentifier ? model : "\(model) (\(modelIdentifier))") }
        parts.append(chipName)
        parts.append(performanceCores > 0 ? "\(totalCores) CPU cores (\(superCores) + \(performanceCores))" : "\(totalCores) CPU cores")
        parts.append(gpuCores.map { "\($0)-core GPU" } ?? gpuName)
        parts.append("\(memoryGB) GB")
        return parts.joined(separator: " · ")
    }

    static let current: HardwareInfo = {
        let total = sysctlInt("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount
        // perflevel0 = fastest cluster, perflevel1 = next (on M5 Pro/Max: super cores / performance cores)
        let level0 = sysctlInt("hw.perflevel0.physicalcpu") ?? total
        let level1 = sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        let memory = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return HardwareInfo(
            chipName: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
            totalCores: total,
            superCores: level0,
            performanceCores: level1,
            gpuName: MTLCreateSystemDefaultDevice()?.name ?? "Unknown GPU",
            memoryGB: memory,
            computerName: (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ProcessInfo.processInfo.hostName,
            modelName: IORegistryInfo.productName() ?? "",
            modelIdentifier: sysctlString("hw.model") ?? "",
            gpuCores: IORegistryInfo.gpuCoreCount()
        )
    }()

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// Reads the Mac's marketing name and GPU core count from the I/O Registry (no admin rights needed).
enum IORegistryInfo {
    /// e.g. "MacBook Pro (16-inch, 2026)" from IODeviceTree:/product.
    static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        if let data = value as? Data {
            let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return value as? String
    }

    static func gpuCoreCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }
}
