import Foundation
import Metal

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
            memoryGB: memory
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
