import Foundation
import Observation

/// Unpaid balance waiting at a pool for one payout address.
struct PoolBalance: Identifiable, Equatable {
    var id: String { "\(pool)|\(coinTag)|\(address)" }
    var pool: String          // "Kryptex", "unMineable", "SupportXMR", "2Miners"
    var coinTag: String       // the coin the balance is in (for unMineable: the payout coin)
    var address: String
    var amount: Double        // whole coins
    var threshold: Double?    // payout threshold, whole coins
}

/// Reads unpaid balances from the pools' public APIs for the addresses this Mac mines to, so the Dashboard
/// can show that mining is landing somewhere real. Read-only, no account or key needed. Units below were
/// checked against live responses (Oct 2026): Kryptex and unMineable report whole coins, SupportXMR
/// piconero (1e-12 XMR), 2Miners' Ravencoin pool 1e-8 RVN.
@MainActor
@Observable
final class PoolBalanceService {
    /// One pool account to look up.
    struct Target: Hashable {
        enum Kind: Hashable { case kryptex(slug: String), unmineable, supportXMR, twoMinersRVN }
        var kind: Kind
        var coinTag: String
        var address: String
    }

    private(set) var balances: [PoolBalance] = []
    private(set) var lastUpdated: Date?
    private(set) var problem: String?
    @ObservationIgnored private var isRefreshing = false

    /// The pool accounts the current settings mine to. Coins paid to a Kryptex *username* (not an address)
    /// are left out – Kryptex's public API looks balances up by address.
    nonisolated static func targets(for s: MinerSettings) -> [Target] {
        var result: [Target] = []
        for coin in CoinCatalog.coins {
            guard let pool = s.pool(for: coin) else { continue }
            if pool.paysViaUnmineable {
                let address = s.unmineableAddress.trimmingCharacters(in: .whitespaces)
                if !address.isEmpty { result.append(Target(kind: .unmineable, coinTag: s.unmineablePayoutCoin, address: address)) }
                continue
            }
            let wallet = s.wallet(for: coin.tag).trimmingCharacters(in: .whitespaces)
            guard !wallet.isEmpty else { continue }
            let host = pool.address.split(separator: ":").first.map(String.init) ?? ""
            if host.hasSuffix(".kryptex.network"), let slug = host.split(separator: ".").first {
                result.append(Target(kind: .kryptex(slug: String(slug)), coinTag: coin.tag, address: wallet))
            } else if pool.id == "supportxmr" {
                result.append(Target(kind: .supportXMR, coinTag: "XMR", address: wallet))
            } else if pool.id == "2miners" && coin.tag == "RVN" {
                result.append(Target(kind: .twoMinersRVN, coinTag: "RVN", address: wallet))
            }
        }
        var seen = Set<Target>()
        return result.filter { seen.insert($0).inserted }
    }

    nonisolated static func url(for t: Target) -> URL? {
        let a = t.address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? t.address
        switch t.kind {
        case .kryptex(let slug): return URL(string: "https://pool.kryptex.com/\(slug)/api/v1/miner/balance/\(a)")
        case .unmineable: return URL(string: "https://api.unminable.com/v4/address/\(a)?coin=\(t.coinTag)")
        case .supportXMR: return URL(string: "https://supportxmr.com/api/miner/\(a)/stats")
        case .twoMinersRVN: return URL(string: "https://rvn.2miners.com/api/accounts/\(a)")
        }
    }

    /// Parses a pool's JSON reply; nil when it doesn't contain a balance.
    nonisolated static func parse(_ data: Data, for t: Target) -> PoolBalance? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func number(_ any: Any?) -> Double? {
            if let n = any as? NSNumber { return n.doubleValue }
            if let s = any as? String { return Double(s) }
            return nil
        }
        switch t.kind {
        case .kryptex:
            guard let total = number(json["total"]) else { return nil }
            return PoolBalance(pool: "Kryptex", coinTag: t.coinTag, address: t.address, amount: total, threshold: number(json["threshold"]))
        case .unmineable:
            guard let d = json["data"] as? [String: Any], let balance = number(d["balance"]) else { return nil }
            return PoolBalance(pool: "unMineable", coinTag: t.coinTag, address: t.address, amount: balance,
                               threshold: number(d["payment_threshold"]))
        case .supportXMR:
            guard let due = number(json["amtDue"]) else { return nil }
            return PoolBalance(pool: "SupportXMR", coinTag: "XMR", address: t.address, amount: due / 1e12, threshold: 0.3)
        case .twoMinersRVN:
            guard let stats = json["stats"] as? [String: Any], let balance = number(stats["balance"]) else { return nil }
            let minPayout = (json["config"] as? [String: Any]).flatMap { number($0["minPayout"]) }
            return PoolBalance(pool: "2Miners", coinTag: "RVN", address: t.address, amount: balance / 1e8,
                               threshold: minPayout.map { $0 / 1e8 })
        }
    }

    func refresh(settings: MinerSettings) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let targets = Self.targets(for: settings)
        guard !targets.isEmpty else {
            balances = []
            problem = nil
            return
        }
        var found: [PoolBalance] = []
        var failures: [String] = []
        // reached == false only when the pool couldn't be reached (network error or server error). A pool that
        // answers but has no balance for the address (never mined there yet) is not a problem.
        await withTaskGroup(of: (target: Target, balance: PoolBalance?, reached: Bool).self) { group in
            for target in targets {
                group.addTask {
                    guard let url = Self.url(for: target) else { return (target, nil, true) }
                    var request = URLRequest(url: url, timeoutInterval: 15)
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    guard let (data, response) = try? await URLSession.shared.data(for: request) else { return (target, nil, false) }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status >= 500 { return (target, nil, false) }
                    return (target, status == 200 ? Self.parse(data, for: target) : nil, true)
                }
            }
            for await result in group {
                if let balance = result.balance { found.append(balance) }
                if !result.reached { failures.append(result.target.coinTag) }
            }
        }
        balances = found.sorted { ($0.pool, $0.coinTag) < ($1.pool, $1.coinTag) }
        problem = failures.isEmpty ? nil : "Couldn't read the pool balance for \(failures.sorted().joined(separator: ", "))"
        lastUpdated = Date()
    }
}
