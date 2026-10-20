import XCTest
@testable import MacDualMiner

final class EarningsCalculatorTests: XCTestCase {
    func testMoneroCoinsPerSecond() {
        // 10 kH/s against difficulty 1e12 (≈8.3 GH/s network) at 0.6 XMR reward, no fees:
        // 1e4 / 1e12 * 0.6 = 6e-9 XMR/s
        let net = NetworkStats(difficulty: 1e12, blockReward: 0.6, height: nil, source: "test")
        let cps = EarningsCalculator.coinsPerSecond(coin: .xmr, hashrate: 10_000, network: net, poolFeePercent: 0, devFeePercent: 0)
        XCTAssertEqual(cps, 6e-9, accuracy: 1e-15)
    }

    func testRavencoinUsesTwoToThe32() {
        let net = NetworkStats(difficulty: 1, blockReward: 1250, height: nil, source: "test")
        let cps = EarningsCalculator.coinsPerSecond(coin: .rvn, hashrate: 4_294_967_296, network: net, poolFeePercent: 0, devFeePercent: 0)
        XCTAssertEqual(cps, 1250, accuracy: 1e-9)
    }

    func testFeesAreApplied() {
        let net = NetworkStats(difficulty: 100, blockReward: 1, height: nil, source: "test")
        let cps = EarningsCalculator.coinsPerSecond(coin: .xmr, hashrate: 100, network: net, poolFeePercent: 1, devFeePercent: 1)
        XCTAssertEqual(cps, 0.99 * 0.99, accuracy: 1e-12)
    }

    func testRavencoinHalvings() {
        XCTAssertEqual(EarningsCalculator.ravencoinReward(atHeight: 100), 5000)
        XCTAssertEqual(EarningsCalculator.ravencoinReward(atHeight: 2_100_000), 2500)
        XCTAssertEqual(EarningsCalculator.ravencoinReward(atHeight: 4_588_318), 1250)
        XCTAssertEqual(EarningsCalculator.ravencoinReward(atHeight: 6_300_000), 625)
    }

    func testSnapshotNetAndBreakEven() {
        let xmr = CoinEarnings(coin: .xmr, hashrate: 1, coinsPerSecond: 1e-6, priceUSD: 300, watts: 50,
                               network: NetworkStats(difficulty: 1, blockReward: 1, height: nil, source: "t"))
        let snap = EarningsSnapshot(coins: [xmr], electricityUSDPerKWh: 0.20, totalWatts: 50)
        // gross: 3e-4 $/s → 25.92 $/day; power: 50 W × 24 h = 1.2 kWh × 0.20 = 0.24 $/day
        XCTAssertEqual(snap.gross(.day), 25.92, accuracy: 1e-9)
        XCTAssertEqual(snap.power(.day), 0.24, accuracy: 1e-9)
        XCTAssertEqual(snap.net(.day), 25.68, accuracy: 1e-9)
        XCTAssertEqual(snap.breakEvenUSDPerKWh!, 21.6, accuracy: 1e-9)
    }
}

final class ParsingTests: XCTestCase {
    func testKawpowHashrateLine() {
        XCTAssertEqual(KawpowController.parseMegahash("  6.31 MH/s | 123456 hashes | 0.1h"), 6.31)
        XCTAssertNil(KawpowController.parseMegahash("[STRATUM] Subscribed"))
    }

    func testKawpowProgressAndHeight() {
        XCTAssertEqual(KawpowController.parseProgress("  [##########----------]  45.0% (12s)"), 45.0)
        XCTAssertEqual(KawpowController.parseHeight("  Height: 4588318, Epoch: 611"), 4588318)
        XCTAssertEqual(KawpowController.parseHeight("  ⛏️  MINING block 4588319..."), 4588319)
    }

    func testRavencoinStatsParsers() {
        let blockbook: [String: Any] = ["backend": ["blocks": 4588318, "difficulty": "123456.78"]]
        XCTAssertEqual(MarketDataService.parseRavencoin(blockbook)?.0, 123456.78)
        XCTAssertEqual(MarketDataService.parseRavencoin(blockbook)?.1, 4588318)
        let insight: [String: Any] = ["info": ["difficulty": 98765.4, "blocks": 10]]
        XCTAssertEqual(MarketDataService.parseRavencoin(insight)?.0, 98765.4)
        XCTAssertEqual(MarketDataService.parseRavencoin(NSNumber(value: 42.5))?.0, 42.5)
    }

    func testWalletValidation() {
        XCTAssertTrue(WalletValidator.isRavencoin("RXissQPZ7cGpZf8sKAzaa7BjF6PhKHHAYn"))
        XCTAssertFalse(WalletValidator.isRavencoin("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2x"))
        let xmr = "4" + String(repeating: "A", count: 94)
        XCTAssertTrue(WalletValidator.isMonero(xmr))
        XCTAssertFalse(WalletValidator.isMonero("4short"))
    }

    func testSettingsLoadKeepsDefaultsForMissingKeys() {
        let data = Data(#"{"xmrWallet":"abc","cpuPreset":"full"}"#.utf8)
        let s = MinerSettings.load(from: data)
        XCTAssertEqual(s.xmrWallet, "abc")
        XCTAssertEqual(s.cpuPreset, .full)
        XCTAssertEqual(s.rvnPool, MinerSettings().rvnPool)
    }

    func testXMRigConfigThreads() {
        var s = MinerSettings()
        s.cpuPreset = .balanced
        s.xmrWallet = "wallet"
        let hw = HardwareInfo(chipName: "Apple M5 Max", totalCores: 18, superCores: 6, performanceCores: 12, gpuName: "M5 Max", memoryGB: 48)
        let config = XMRigController.makeConfig(settings: s, hardware: hw, port: 1, token: "t")
        let cpu = config["cpu"] as? [String: Any]
        XCTAssertEqual((cpu?["rx"] as? [Int])?.count, 12)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: config))
    }
}
