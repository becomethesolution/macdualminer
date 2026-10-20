import Foundation

/// Hashrates measured on real Macs and published on cryptominingonmacs.com.
/// Used as starting estimates until the app has benchmarked this Mac itself.
struct ReferenceHashrate {
    let chip: String           // matched against the CPU brand string, e.g. "Apple M5 Max"
    let engine: EngineKind
    let hashrate: Double       // H/s (for UselethMiner: CPU part)
    let gpuHashrate: Double?   // UselethMiner GPU part
    let note: String
    let source: String         // topic URL on cryptominingonmacs.com
}

enum ReferenceHashrates {
    static let all: [ReferenceHashrate] = [
        // 2026 MacBook Pro 16" M5 Max, 18-CPU / 40-GPU – t=169
        ReferenceHashrate(chip: "Apple M5 Max", engine: .xmrig, hashrate: 8_910, gpuHashrate: nil,
                          note: "XMRig 6.26.0, 18 threads, High Power mode", source: "https://cryptominingonmacs.com/viewtopic.php?t=169"),
        ReferenceHashrate(chip: "Apple M5 Max", engine: .ethminer, hashrate: 41_300_000, gpuHashrate: nil,
                          note: "ethminer-m1 0.19, OpenCL", source: "https://cryptominingonmacs.com/viewtopic.php?t=169"),
        ReferenceHashrate(chip: "Apple M5 Max", engine: .kawpow, hashrate: 14_420_000, gpuHashrate: nil,
                          note: "KawPow 14.42 MH/s measured with MacMiner; kawpow-metal not yet tested", source: "https://cryptominingonmacs.com/viewtopic.php?t=169"),

        // 2024 MacBook Pro 16" M4 Max, 16-CPU / 40-GPU – t=164
        ReferenceHashrate(chip: "Apple M4 Max", engine: .xmrig, hashrate: 8_390, gpuHashrate: nil,
                          note: "XMRig 6.22.2, 16 threads", source: "https://cryptominingonmacs.com/viewtopic.php?t=164"),
        ReferenceHashrate(chip: "Apple M4 Max", engine: .ethminer, hashrate: 32_600_000, gpuHashrate: nil,
                          note: "ethminer-m1 0.19, OpenCL", source: "https://cryptominingonmacs.com/viewtopic.php?t=164"),
        ReferenceHashrate(chip: "Apple M4 Max", engine: .useleth, hashrate: 8_000_000, gpuHashrate: 33_000_000,
                          note: "UselethMiner 0.23, armv8af 20 threads + Metal", source: "https://cryptominingonmacs.com/viewtopic.php?t=164"),

        // 2025 Mac Studio M3 Ultra, 32-CPU / 80-GPU – t=166
        ReferenceHashrate(chip: "Apple M3 Ultra", engine: .xmrig, hashrate: 12_400, gpuHashrate: nil,
                          note: "XMRig 6.22.2", source: "https://cryptominingonmacs.com/viewtopic.php?t=166"),
        ReferenceHashrate(chip: "Apple M3 Ultra", engine: .kawpow, hashrate: 21_570_000, gpuHashrate: nil,
                          note: "KawPow measured with MacMiner", source: "https://cryptominingonmacs.com/viewtopic.php?t=166"),
        ReferenceHashrate(chip: "Apple M3 Ultra", engine: .ethminer, hashrate: 50_700_000, gpuHashrate: nil,
                          note: "Ethash measured with MacMiner", source: "https://cryptominingonmacs.com/viewtopic.php?t=166"),
        ReferenceHashrate(chip: "Apple M3 Ultra", engine: .useleth, hashrate: 20_900_000, gpuHashrate: 55_600_000,
                          note: "UselethMiner 0.23", source: "https://cryptominingonmacs.com/viewtopic.php?t=166"),

        // 2023 MacBook Pro 16" M3 Max – t=161
        ReferenceHashrate(chip: "Apple M3 Max", engine: .xmrig, hashrate: 7_250, gpuHashrate: nil,
                          note: "XMRig 6.20.0", source: "https://cryptominingonmacs.com/viewtopic.php?t=161"),

        // Mac Studio M1 Ultra – t=156
        ReferenceHashrate(chip: "Apple M1 Ultra", engine: .xmrig, hashrate: 5_800, gpuHashrate: nil,
                          note: "XMRig", source: "https://cryptominingonmacs.com/viewtopic.php?t=156"),
        ReferenceHashrate(chip: "Apple M1 Ultra", engine: .useleth, hashrate: 18_600_000, gpuHashrate: 14_200_000,
                          note: "UselethMiner", source: "https://cryptominingonmacs.com/viewtopic.php?t=156"),
    ]

    /// Best match for this Mac's chip, longest name first so "M5 Max" doesn't match a plain "M5".
    /// References are all for each engine's main algorithm (RandomX for XMRig).
    static func lookup(chip: String, engine: EngineKind, algorithm: Algorithm? = nil) -> ReferenceHashrate? {
        if let algorithm, algorithm != engine.primaryAlgorithm { return nil }
        return all.filter { $0.engine == engine && chip.localizedCaseInsensitiveContains($0.chip) }
            .max { $0.chip.count < $1.chip.count }
    }
}
