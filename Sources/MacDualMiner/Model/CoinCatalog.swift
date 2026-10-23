import Foundation

enum Device: String, Codable, CaseIterable, Identifiable {
    case cpu, gpu
    var id: String { rawValue }
    var label: String { self == .cpu ? "CPU" : "GPU" }
}

/// Hashing algorithm. Raw values match WhatToMine's `algorithm` field.
enum Algorithm: String, Codable, CaseIterable, Identifiable {
    case randomX = "RandomX"
    case kawPow = "KawPow"
    case ethash = "Ethash"
    case ghostRider = "GhostRider"
    /// Tari's standalone RandomX chain. Same hashing as RandomX (the pool supplies Tari's seed), so it
    /// shares RandomX's benchmarks; only the market data differs.
    case tariRandomX = "TariRandomX"
    var id: String { rawValue }

    /// The algorithm whose hashrate and power numbers apply.
    var hashFamily: Algorithm { self == .tariRandomX ? .randomX : self }
}

/// One engine running one algorithm – hashrates are measured and estimated per pair.
struct EngineAlgo: Hashable, Codable {
    var engine: EngineKind
    var algorithm: Algorithm
    var key: String { "\(engine.rawValue):\(algorithm.rawValue)" }

    init(_ engine: EngineKind, _ algorithm: Algorithm) {
        self.engine = engine
        self.algorithm = algorithm
    }

    /// Parses "xmrig:RandomX"; a bare "xmrig" (0.2.x benchmark files) means the engine's main algorithm.
    init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard let engine = EngineKind(rawValue: parts[0]) else { return nil }
        if parts.count == 2 {
            guard let algorithm = Algorithm(rawValue: parts[1]) else { return nil }
            self.init(engine, algorithm)
        } else {
            self.init(engine, engine.primaryAlgorithm)
        }
    }

    static var all: [EngineAlgo] {
        EngineKind.allCases.flatMap { e in e.algorithms.map { EngineAlgo(e, $0) } }
    }
}

/// A mining program bundled with the app.
enum EngineKind: String, Codable, CaseIterable, Identifiable {
    case xmrig, kawpow, ethminer, useleth
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xmrig: return "XMRig"
        case .kawpow: return "kawpow-metal"
        case .ethminer: return "ethminer-m1"
        case .useleth: return "UselethMiner"
        }
    }

    var algorithms: [Algorithm] {
        switch self {
        case .xmrig: return [.randomX, .ghostRider]
        case .kawpow: return [.kawPow]
        case .ethminer, .useleth: return [.ethash]
        }
    }

    var primaryAlgorithm: Algorithm { algorithms[0] }

    /// Which parts of the chip the engine occupies while running.
    var devices: Set<Device> {
        switch self {
        case .xmrig: return [.cpu]
        case .kawpow, .ethminer: return [.gpu]
        case .useleth: return [.cpu, .gpu]
        }
    }

    var deviceLabel: String {
        devices.count == 2 ? "CPU + GPU" : (devices.contains(.cpu) ? "CPU" : "GPU")
    }

    /// Share of hashes the engine itself keeps as a developer fee.
    var devFeePercent: Double {
        switch self {
        case .xmrig, .useleth: return 1
        case .kawpow, .ethminer: return 0
        }
    }

    var backend: String {
        switch self {
        case .xmrig: return "CPU (ARMv8 + AES)"
        case .kawpow: return "Metal"
        case .ethminer: return "OpenCL"
        case .useleth: return "ARMv8 + Metal"
        }
    }

    var executable: URL {
        switch self {
        case .xmrig: return AppPaths.xmrigExecutable
        case .kawpow: return AppPaths.kawpowExecutable
        case .ethminer: return AppPaths.ethminerExecutable
        case .useleth: return AppPaths.uselethExecutable
        }
    }
}

/// How a pool wants the login built. `{wallet}` and `{worker}` are substituted.
struct PoolPreset: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var address: String          // host:port
    var tls: Bool
    var feePercent: Double
    var userTemplate: String     // e.g. "{wallet}/{worker}" (Kryptex) or "{wallet}.{worker}"
    var acceptsKryptexAccount: Bool = false
    /// unMineable: paid in another coin to the payout address in Coins & Wallets › Payouts.
    var paysViaUnmineable: Bool = false
}

struct CoinSpec: Identifiable, Hashable {
    let tag: String
    let name: String
    let algorithm: Algorithm
    /// Bundled engines that can mine it ([] = algorithm variant not supported by any bundled engine).
    let engines: [EngineKind]
    let pools: [PoolPreset]
    let walletHint: String
    let note: String?
    let experimental: Bool
    /// XMRig `algo` value (RandomX family only).
    let xmrigAlgo: String?

    var id: String { tag }
    var isSupported: Bool { !engines.isEmpty }
}

/// Coin whose algorithm WhatToMine lists but no bundled engine can mine (shown in the check, greyed out).
struct UnsupportedCoin: Hashable {
    let tag: String
    let algorithmName: String
    let reason: String
}

/// Coins unMineable can pay Monero mining out in, to an address in a wallet such as Trust Wallet.
enum UnmineablePayout {
    static let coins: [(tag: String, name: String)] = [
        ("DOGE", "Dogecoin"), ("LTC", "Litecoin"), ("BTC", "Bitcoin"), ("BCH", "Bitcoin Cash"), ("TRX", "Tron"),
        ("SOL", "Solana"), ("ADA", "Cardano"), ("DASH", "Dash"), ("DGB", "DigiByte"), ("ETC", "Ethereum Classic"),
        ("RVN", "Ravencoin"), ("ZEC", "Zcash"),
    ]
}

enum CoinCatalog {
    private static let kryptex = "Kryptex"

    static let coins: [CoinSpec] = [
        // MARK: CPU – RandomX via XMRig
        CoinSpec(tag: "XMR", name: "Monero", algorithm: .randomX, engines: [.xmrig],
                 pools: [
                    PoolPreset(id: "supportxmr", name: "SupportXMR", address: "pool.supportxmr.com:443", tls: true, feePercent: 0.6, userTemplate: "{wallet}"),
                    PoolPreset(id: "kryptex", name: kryptex, address: "xmr.kryptex.network:7029", tls: false, feePercent: 1, userTemplate: "{wallet}/{worker}", acceptsKryptexAccount: true),
                    PoolPreset(id: "unmineable", name: "unMineable (paid in another coin)", address: "rx.unmineable.com:443", tls: true, feePercent: 1, userTemplate: "{wallet}.{worker}", paysViaUnmineable: true),
                 ],
                 walletHint: "4… or 8… (95 characters)", note: nil, experimental: false, xmrigAlgo: "rx/0"),
        CoinSpec(tag: "XTM", name: "Tari (RandomX)", algorithm: .tariRandomX, engines: [.xmrig],
                 pools: [PoolPreset(id: "kryptex", name: kryptex, address: "xtm-rx.kryptex.network:7038", tls: false, feePercent: 1, userTemplate: "{wallet}/{worker}")],
                 walletHint: "Tari wallet address", note: "Tari's own RandomX chain (not the merge-mined bonus)", experimental: true, xmrigAlgo: "rx/0"),
        CoinSpec(tag: "ZEPH", name: "Zephyr", algorithm: .randomX, engines: [.xmrig],
                 pools: [PoolPreset(id: "kryptex", name: kryptex, address: "zeph.kryptex.network:7030", tls: false, feePercent: 1, userTemplate: "{wallet}/{worker}", acceptsKryptexAccount: true)],
                 walletHint: "ZEPH… address", note: nil, experimental: false, xmrigAlgo: "rx/0"),
        CoinSpec(tag: "QRL", name: "Quantum Resistant Ledger", algorithm: .randomX, engines: [.xmrig], pools: [],
                 walletHint: "Q… address", note: "Add a QRL pool under Coins & Wallets", experimental: false, xmrigAlgo: "rx/0"),
        CoinSpec(tag: "EPIC", name: "Epic Cash", algorithm: .randomX, engines: [.xmrig], pools: [],
                 walletHint: "Pool login", note: "Add an Epic Cash RandomX pool under Coins & Wallets", experimental: true, xmrigAlgo: "rx/0"),
        CoinSpec(tag: "ETI", name: "Etica", algorithm: .randomX, engines: [.xmrig], pools: [],
                 walletHint: "0x… address", note: "Add an Etica pool under Coins & Wallets", experimental: true, xmrigAlgo: "rx/0"),

        // MARK: CPU – GhostRider via XMRig
        CoinSpec(tag: "RTM", name: "Raptoreum", algorithm: .ghostRider, engines: [.xmrig], pools: [],
                 walletHint: "R… address", note: "Add a Raptoreum pool (e.g. flockpool) under Coins & Wallets – very thin trading volume",
                 experimental: true, xmrigAlgo: "gr"),

        // MARK: GPU – KawPow via kawpow-metal
        CoinSpec(tag: "RVN", name: "Ravencoin", algorithm: .kawPow, engines: [.kawpow],
                 pools: [PoolPreset(id: "2miners", name: "2Miners", address: "rvn.2miners.com:6060", tls: false, feePercent: 1, userTemplate: "{wallet}.{worker}")],
                 walletHint: "R… (34 characters)", note: nil, experimental: false, xmrigAlgo: nil),
        CoinSpec(tag: "QUAI", name: "Quai (KawPow)", algorithm: .kawPow, engines: [.kawpow],
                 pools: [PoolPreset(id: "kryptex", name: kryptex, address: "quai-kawpow.kryptex.network:7043", tls: false, feePercent: 1, userTemplate: "{wallet}/{worker}", acceptsKryptexAccount: true)],
                 walletHint: "0x… Quai address", note: "Kryptex can't auto-convert QUAI payouts", experimental: true, xmrigAlgo: nil),
        CoinSpec(tag: "NEOX", name: "Neoxa", algorithm: .kawPow, engines: [.kawpow], pools: [],
                 walletHint: "G… address", note: "Add a Neoxa pool under Coins & Wallets", experimental: false, xmrigAlgo: nil),
        CoinSpec(tag: "XNA", name: "Neurai", algorithm: .kawPow, engines: [.kawpow], pools: [],
                 walletHint: "N… address", note: "Add a Neurai pool under Coins & Wallets", experimental: false, xmrigAlgo: nil),
        CoinSpec(tag: "KRGN", name: "Kerrigan", algorithm: .kawPow, engines: [.kawpow], pools: [],
                 walletHint: "Address", note: "Add a Kerrigan pool under Coins & Wallets", experimental: true, xmrigAlgo: nil),

        // MARK: GPU / CPU+GPU – Ethash via ethminer-m1 or UselethMiner
        CoinSpec(tag: "ETHW", name: "EthereumPoW", algorithm: .ethash, engines: [.ethminer, .useleth],
                 pools: [PoolPreset(id: "kryptex", name: kryptex, address: "ethw.kryptex.network:7034", tls: false, feePercent: 1, userTemplate: "{wallet}/{worker}", acceptsKryptexAccount: true)],
                 walletHint: "0x… address", note: nil, experimental: false, xmrigAlgo: nil),
        CoinSpec(tag: "OCTA", name: "OctaSpace", algorithm: .ethash, engines: [.ethminer], pools: [],
                 walletHint: "0x… address", note: "Add an OctaSpace pool under Coins & Wallets", experimental: true, xmrigAlgo: nil),
        CoinSpec(tag: "QKC", name: "QuarkChain", algorithm: .ethash, engines: [.ethminer], pools: [],
                 walletHint: "0x… address", note: "Add a QuarkChain pool under Coins & Wallets", experimental: true, xmrigAlgo: nil),
    ]

    /// Shown in the profit check so it's clear why they're not options.
    static let unsupported: [UnsupportedCoin] = [
        UnsupportedCoin(tag: "ERG", algorithmName: "Autolykos", reason: "Only MacMiner (closed GUI app) mines Autolykos on Macs"),
        UnsupportedCoin(tag: "ETC", algorithmName: "Etchash", reason: "ethminer-m1 and UselethMiner only do Ethash, not Etchash"),
        UnsupportedCoin(tag: "MEWC", algorithmName: "MeowPow", reason: "MeowPow is a KawPow variant kawpow-metal doesn't implement"),
        UnsupportedCoin(tag: "XEL", algorithmName: "XelisHash", reason: "No Apple Silicon build of a Xelis miner yet"),
        UnsupportedCoin(tag: "VRSC", algorithmName: "VerusHash", reason: "No Apple Silicon build of a Verus miner yet"),
        UnsupportedCoin(tag: "XDAG", algorithmName: "RandomX", reason: "XDAG needs a special XMRig fork"),
    ]

    static func coin(_ tag: String) -> CoinSpec? { coins.first { $0.tag == tag } }

    static func coins(for engine: EngineKind) -> [CoinSpec] { coins.filter { $0.engines.contains(engine) } }
}

/// A specific way to mine: which engine, which coin.
struct MiningOption: Hashable, Identifiable, Codable {
    var engine: EngineKind
    var coinTag: String
    var id: String { "\(engine.rawValue):\(coinTag)" }

    init(engine: EngineKind, coinTag: String) {
        self.engine = engine
        self.coinTag = coinTag
    }

    init?(id: String) {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let engine = EngineKind(rawValue: parts[0]) else { return nil }
        self.init(engine: engine, coinTag: parts[1])
    }

    var coin: CoinSpec? { CoinCatalog.coin(coinTag) }
    var engineAlgo: EngineAlgo { EngineAlgo(engine, coin?.algorithm.hashFamily ?? engine.primaryAlgorithm) }
    var label: String { "\(coin?.name ?? coinTag) (\(coinTag)) · \(engine.displayName)" }

    static var all: [MiningOption] {
        CoinCatalog.coins.flatMap { coin in coin.engines.map { MiningOption(engine: $0, coinTag: coin.tag) } }
    }
}

/// Everything an engine needs to start mining one coin on one pool.
struct MiningJob: Equatable {
    var option: MiningOption
    var poolAddress: String
    var tls: Bool
    var poolFeePercent: Double
    var login: String            // the pool username (wallet[.worker] etc.)
    var worker: String
    var password: String { worker.isEmpty ? "x" : worker }

    var signature: String { [option.id, poolAddress, String(tls), login].joined(separator: "|") }
}

enum PoolLogin {
    static func build(template: String, wallet: String, worker: String) -> String {
        template
            .replacingOccurrences(of: "{wallet}", with: wallet.trimmingCharacters(in: .whitespaces))
            .replacingOccurrences(of: "{worker}", with: worker.isEmpty ? "mac" : worker)
    }
}
