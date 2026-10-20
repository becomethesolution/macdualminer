import Foundation
import Observation

/// Fetches live USD prices and network difficulty / block reward, with fallbacks.
@MainActor
@Observable
final class MarketDataService {
    private(set) var prices: [Coin: Double] = [:]
    private(set) var priceSource: String?
    private(set) var network: [Coin: NetworkStats] = [:]
    private(set) var lastUpdated: Date?
    private(set) var problems: [String] = []
    private(set) var isRefreshing = false

    @ObservationIgnored private var task: Task<Void, Never>?

    func start(settings: @escaping @MainActor () -> MinerSettings) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(settings: settings())
                let wait = max(30, settings().marketRefreshSeconds)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func refresh(settings: MinerSettings) async {
        isRefreshing = true
        defer { isRefreshing = false }
        var issues: [String] = []

        async let priceResult = Self.fetchPrices()
        async let xmrResult = Self.fetchMoneroStats(nodeURL: settings.xmrNodeURL)
        async let rvnResult = Self.fetchRavencoinStats(customURL: settings.customRVNStatsURL)

        if let fetched = await priceResult {
            prices = fetched.0
            priceSource = fetched.1
        } else {
            issues.append("Couldn't fetch prices (CoinGecko and Coinpaprika both failed)")
        }

        if var xmr = await xmrResult {
            if settings.xmrDifficultyOverride > 0 { xmr.difficulty = settings.xmrDifficultyOverride; xmr.source += " (difficulty overridden)" }
            network[.xmr] = xmr
        } else if settings.xmrDifficultyOverride > 0 {
            network[.xmr] = NetworkStats(difficulty: settings.xmrDifficultyOverride, blockReward: EarningsCalculator.moneroTailReward, height: nil, source: "Manual difficulty")
        } else {
            issues.append("Couldn't fetch Monero network difficulty – set a manual value in Settings › Earnings")
        }

        if var rvn = await rvnResult {
            if settings.rvnDifficultyOverride > 0 { rvn.difficulty = settings.rvnDifficultyOverride; rvn.source += " (difficulty overridden)" }
            network[.rvn] = rvn
        } else if settings.rvnDifficultyOverride > 0 {
            network[.rvn] = NetworkStats(difficulty: settings.rvnDifficultyOverride, blockReward: EarningsCalculator.ravencoinReward(atHeight: nil), height: nil, source: "Manual difficulty")
        } else {
            issues.append("Couldn't fetch Ravencoin network difficulty – set a manual value in Settings › Earnings")
        }

        problems = issues
        lastUpdated = Date()
    }

    // MARK: - Prices

    nonisolated static func fetchPrices() async -> ([Coin: Double], String)? {
        // 1) CoinGecko
        if let json = await getJSON("https://api.coingecko.com/api/v3/simple/price?ids=monero,ravencoin&vs_currencies=usd") as? [String: Any],
           let xmr = number((json["monero"] as? [String: Any])?["usd"]),
           let rvn = number((json["ravencoin"] as? [String: Any])?["usd"]) {
            return ([.xmr: xmr, .rvn: rvn], "CoinGecko")
        }
        // 2) Coinpaprika
        async let xmrTicker = getJSON("https://api.coinpaprika.com/v1/tickers/xmr-monero")
        async let rvnTicker = getJSON("https://api.coinpaprika.com/v1/tickers/rvn-ravencoin")
        let usd: (Any?) -> Double? = { (($0 as? [String: Any])?["quotes"] as? [String: Any]).flatMap { ($0["USD"] as? [String: Any]).flatMap { number($0["price"]) } } }
        if let xmr = usd(await xmrTicker), let rvn = usd(await rvnTicker) {
            return ([.xmr: xmr, .rvn: rvn], "Coinpaprika")
        }
        return nil
    }

    // MARK: - Monero network

    nonisolated static func fetchMoneroStats(nodeURL: String) async -> NetworkStats? {
        // 1) SupportXMR pool API (nodejs-pool): { difficulty, height, value (atomic units) }
        if let json = await getJSON("https://www.supportxmr.com/api/network/stats") as? [String: Any],
           let difficulty = number(json["difficulty"]), difficulty > 0 {
            let reward = number(json["value"]).map { $0 / 1e12 } ?? EarningsCalculator.moneroTailReward
            return NetworkStats(difficulty: difficulty,
                                blockReward: reward > 0 && reward < 100 ? reward : EarningsCalculator.moneroTailReward,
                                height: number(json["height"]).map { Int($0) },
                                source: "SupportXMR API")
        }
        // 2) A Monero node's JSON-RPC
        if let url = URL(string: nodeURL), !nodeURL.isEmpty {
            let body: [String: Any] = ["jsonrpc": "2.0", "id": "0", "method": "get_last_block_header"]
            if let json = await postJSON(url, body: body) as? [String: Any],
               let header = (json["result"] as? [String: Any])?["block_header"] as? [String: Any],
               let difficulty = number(header["difficulty"]), difficulty > 0 {
                let reward = number(header["reward"]).map { $0 / 1e12 } ?? EarningsCalculator.moneroTailReward
                return NetworkStats(difficulty: difficulty, blockReward: reward,
                                    height: number(header["height"]).map { Int($0) },
                                    source: "Monero node (\(url.host ?? nodeURL))")
            }
        }
        return nil
    }

    // MARK: - Ravencoin network

    nonisolated static func fetchRavencoinStats(customURL: String) async -> NetworkStats? {
        var candidates: [(String, String)] = []
        if !customURL.isEmpty { candidates.append((customURL, "Custom URL")) }
        candidates += [
            ("https://blockbook.ravencoin.org/api/", "Ravencoin Blockbook"),
            ("https://api.ravencoin.org/api/status?q=getInfo", "Ravencoin Insight API"),
            ("https://rvn.cryptoscope.io/api/getdifficulty/", "Cryptoscope explorer"),
        ]
        for (urlString, label) in candidates {
            guard let raw = await getJSON(urlString) else { continue }
            if let parsed = parseRavencoin(raw), parsed.0 > 0 {
                return NetworkStats(difficulty: parsed.0,
                                    blockReward: EarningsCalculator.ravencoinReward(atHeight: parsed.1),
                                    height: parsed.1, source: label)
            }
        }
        return nil
    }

    /// Understands Blockbook (`backend.difficulty`), Insight (`info.difficulty` / `difficulty`)
    /// and plain-number responses.
    nonisolated static func parseRavencoin(_ raw: Any) -> (Double, Int?)? {
        if let value = number(raw) { return (value, nil) }
        guard let json = raw as? [String: Any] else { return nil }
        let containers: [[String: Any]] = [
            json["backend"] as? [String: Any],
            json["info"] as? [String: Any],
            json,
        ].compactMap { $0 }
        for container in containers {
            if let difficulty = number(container["difficulty"]) {
                let height = number(container["blocks"] ?? container["height"]).map { Int($0) }
                return (difficulty, height)
            }
        }
        return nil
    }

    // MARK: - HTTP helpers

    nonisolated static func getJSON(_ urlString: String) async -> Any? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MacDualMiner/1.0", forHTTPHeaderField: "User-Agent")
        return await perform(request)
    }

    nonisolated static func postJSON(_ url: URL, body: [String: Any]) async -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await perform(request)
    }

    nonisolated private static func perform(_ request: URLRequest) async -> Any? {
        guard let result = try? await URLSession.shared.data(for: request),
              case let (data, response) = result,
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Accepts numbers or numeric strings.
    nonisolated static func number(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}
