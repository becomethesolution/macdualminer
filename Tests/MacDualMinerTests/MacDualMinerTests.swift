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
        let xmr = CoinEarnings(tag: "XMR", name: "Monero", algorithm: .randomX, engine: .xmrig, hashrate: 1,
                               coinsPerSecond: 1e-6, priceUSD: 300, watts: 50, networkHashrate: 1, blockReward: 1, dataSource: "t")
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

    func testXMRigConfigThreadsFollowCPUPowerLevel() {
        var s = MinerSettings()
        s.cpuPowerLevel = 7
        s.wallets["ZEPH"] = "ZEPHwallet"
        let hw = HardwareInfo(chipName: "Apple M5 Max", totalCores: 18, superCores: 6, performanceCores: 12, gpuName: "M5 Max", memoryGB: 48)
        let job = s.job(for: MiningOption(engine: .xmrig, coinTag: "ZEPH"))!
        let config = XMRigController.makeConfig(job: job, settings: s, hardware: hw, port: 1, token: "t")
        let cpu = config["cpu"] as? [String: Any]
        XCTAssertEqual((cpu?["rx"] as? [Int])?.count, 13)          // 18 × 0.7 = 12.6 → 13
        let pool = (config["pools"] as? [[String: Any]])?.first
        XCTAssertEqual(pool?["url"] as? String, "zeph.kryptex.network:7030")
        XCTAssertEqual(pool?["user"] as? String, "ZEPHwallet/m5max")
        XCTAssertEqual(pool?["algo"] as? String, "rx/0")
        XCTAssertNil(pool?["coin"])
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: config))
    }
}

final class EngineParsingTests: XCTestCase {
    @MainActor func testEthminerHashrateAndShares() {
        let e = EthminerController()
        e.parse("m 22:06:20 0:00 A0 41.56 Mh - cl0 41.56")
        XCTAssertEqual(e.meter.latest!, 41_560_000, accuracy: 1)
        e.parse("m 11:27:50 0:01 A12:R1 32.57 Mh - cl0 32.57")
        XCTAssertEqual(e.acceptedShares, 12)
        XCTAssertEqual(e.rejectedShares, 1)
    }

    func testEthminerPoolURLEncodesKryptexSlash() {
        let job = MiningJob(option: MiningOption(engine: .ethminer, coinTag: "ETHW"), poolAddress: "ethw.kryptex.network:7034",
                            tls: false, poolFeePercent: 1, login: "0xabc/m5max", worker: "m5max")
        XCTAssertEqual(EthminerController.poolURL(for: job), "stratum://0xabc%2Fm5max:m5max@ethw.kryptex.network:7034")
    }

    @MainActor func testUselethStatusLine() {
        let u = UselethController()
        u.parse("[2024-11-24 11:20:52][STATUS] CPU[ 7436837 h/s :: 1155 s/a :: 371841 h/s/t :: 20 t :: 64 sz :: 56.74 GB/s ] GPU[ 31982661 h/s :: 268 s/a :: 128 sz :: 244.0 GB/s ]")
        XCTAssertEqual(u.cpuMeter.latest, 7_436_837)
        XCTAssertEqual(u.gpuMeter.latest, 31_982_661)
    }

    func testUselethArguments() {
        let job = MiningJob(option: MiningOption(engine: .useleth, coinTag: "ETHW"), poolAddress: "ethw.kryptex.network:7034",
                            tls: false, poolFeePercent: 1, login: "acct/mac", worker: "mac")
        XCTAssertEqual(UselethController.arguments(for: job, threads: 13).prefix(3), ["acct/mac@ethw.kryptex.network:7034", "-t", "13"])
    }
}

final class ProfitTests: XCTestCase {
    private func market(_ tag: String, _ algo: String, nethash: Double, reward: Double, blockTime: Double, btc: Double, vol: Double = 10) -> CoinMarket {
        CoinMarket(tag: tag, name: tag, algorithm: algo, blockTime: blockTime, blockReward: reward, blockReward24: nil,
                   networkHashrate: nethash, exchangeRateBTC: btc, exchangeRateBTC24: nil, volumeBTC: vol, lagging: false)
    }

    func testWhatToMineParsing() {
        let json = #"{"coins":{"Monero":{"tag":"XMR","algorithm":"RandomX","block_time":"124.0","block_reward":0.6,"nethash":6000000000,"exchange_rate":0.0074,"exchange_rate_vol":55.4,"lagging":false},"Nicehash-RandomX":{"tag":"NICEHASH","algorithm":"RandomX","block_time":"1","block_reward":1,"nethash":1,"exchange_rate":1}}}"#
        let parsed = WhatToMineParser.parse(Data(json.utf8))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.tag, "XMR")
        XCTAssertEqual(parsed.first?.blockTime, 124)
    }

    func testCoinsPerSecondUsesNetworkShare() {
        let m = market("XMR", "RandomX", nethash: 6e9, reward: 0.6, blockTime: 120, btc: 0.0075)
        // 9 kH/s of 6 GH/s = 1.5e-6 share × 0.6 XMR / 120 s
        XCTAssertEqual(m.coinsPerSecond(hashrate: 9_000, useDayAverages: true), 7.5e-9, accuracy: 1e-15)
    }

    private func inputs(_ s: MinerSettings) -> ProfitInputs {
        ProfitInputs(
            settings: s,
            markets: ["XMR": market("XMR", "RandomX", nethash: 6e9, reward: 0.6, blockTime: 120, btc: 0.0075),
                      "RVN": market("RVN", "KawPow", nethash: 4e13, reward: 1250, blockTime: 60, btc: 0.000018),
                      "QUAI": market("QUAI", "KawPow", nethash: 1e13, reward: 10, blockTime: 10, btc: 0.0001),
                      "ETHW": market("ETHW", "Ethash", nethash: 2.7e12, reward: 2, blockTime: 13, btc: 0.000003, vol: 0.1)],
            btcUSD: 80_000,
            estimates: [.xmrig: HashrateEstimate(cpu: 9_000, gpu: 0, watts: 50, source: .benchmark, note: nil),
                        .kawpow: HashrateEstimate(cpu: 0, gpu: 14e6, watts: 60, source: .reference, note: nil),
                        .ethminer: HashrateEstimate(cpu: 0, gpu: 41e6, watts: 60, source: .reference, note: nil),
                        .useleth: HashrateEstimate(cpu: 8e6, gpu: 33e6, watts: 110, source: .reference, note: nil)],
            installed: Set(EngineKind.allCases))
    }

    func testRankingFlagsLiquidityAndMissingWallets() {
        var s = MinerSettings()
        s.wallets = ["XMR": "4wallet", "RVN": "Rwallet"]
        let ranked = ProfitPlanner.rank(inputs(s))
        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
        XCTAssertEqual(byID["xmrig:XMR"]?.status, .ready)
        XCTAssertEqual(byID["kawpow:QUAI"]?.status, .needsSetup("Needs a QUAI wallet"))
        XCTAssertEqual(byID["ethminer:ETHW"]?.status, .lowLiquidity)
        XCTAssertEqual(byID["kawpow:NEOX"]?.status, .noMarketData)
        XCTAssertTrue(ranked.first!.isEligible)
    }

    func testBestPlanUsesKryptexAccountAndPicksBetterKawPowCoin() {
        var s = MinerSettings()
        s.wallets = ["XMR": "4wallet", "RVN": "Rwallet"]
        s.kryptexAccount = "vincent"
        let plan = ProfitPlanner.bestPlan(ProfitPlanner.rank(inputs(s)), skipUnprofitable: false)
        XCTAssertEqual(plan.option(on: .cpu)?.id, "xmrig:XMR")
        XCTAssertEqual(plan.option(on: .gpu)?.id, "kawpow:QUAI")   // QUAI earns more than RVN in this fixture
        XCTAssertEqual(s.job(for: MiningOption(engine: .kawpow, coinTag: "QUAI"))?.login, "vincent/m5max")
    }

    func testHysteresis() {
        XCTAssertFalse(ProfitPlanner.shouldSwitch(currentNet: 1.00, bestNet: 1.05, marginPercent: 10))
        XCTAssertTrue(ProfitPlanner.shouldSwitch(currentNet: 1.00, bestNet: 1.20, marginPercent: 10))
        XCTAssertTrue(ProfitPlanner.shouldSwitch(currentNet: -0.10, bestNet: 0.05, marginPercent: 10))
        XCTAssertFalse(ProfitPlanner.shouldSwitch(currentNet: 0.5, bestNet: 0.4, marginPercent: 10))
    }

    func testPowerLevels() {
        var s = MinerSettings()
        s.cpuPowerLevel = 10
        XCTAssertEqual(s.cpuThreads(totalCores: 18), 18)
        s.cpuPowerLevel = 1
        XCTAssertEqual(s.cpuThreads(totalCores: 18), 2)
        s.gpuPowerLevel = 5
        XCTAssertEqual(s.gpuPowerFactor, 0.5)
        s.gpuWattsEstimate = 60
        XCTAssertEqual(ProfitPlanner.wattsEstimate(.kawpow, settings: s), 30)
    }

    func testReferenceLookupPrefersExactChip() {
        XCTAssertEqual(ReferenceHashrates.lookup(chip: "Apple M5 Max", engine: .xmrig)?.hashrate, 8_910)
        XCTAssertNil(ReferenceHashrates.lookup(chip: "Apple M5", engine: .xmrig))
    }
}
