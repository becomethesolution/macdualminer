# MacDualMiner

A lightweight native macOS app that mines on **both halves of an Apple Silicon chip at once**, tuned for the **M5 Max**:

| Part of the chip | Engine | Coin | Algorithm |
|---|---|---|---|
| CPU (18 cores: 6 super + 12 performance) | [XMRig](https://github.com/xmrig/xmrig) | Monero (XMR) | RandomX |
| GPU (Metal) | [kawpow-metal](https://github.com/imperatormk/kawpow-metal) | Ravencoin (RVN) | KawPow |

It also includes a **real-time earnings calculator**. It combines your live hashrate with each coin's live network difficulty, block reward and USD price, then subtracts pool fees, the XMRig dev fee and your electricity cost. The result is a realistic **USD per hour, day, week, month and year**.

> **Reality check:** a Mac is not a profitable mining rig. Expect cents per day, and possibly a net loss once electricity is included. The earnings tab is built to show that honestly. Mining also keeps the chip hot and fans busy for as long as it runs.

---

## Features

- **One window + menu bar**: start or stop with a click (⇧⌘M). The menu bar shows live net $/day.
- **Live dashboard**: CPU hashrate (10s/60s/15m), GPU MH/s, shares, pool, DAG progress, power draw, thermals.
- **Earnings tab**:
  - Live prices from CoinGecko, with Coinpaprika as a fallback.
  - Live network difficulty: Monero from SupportXMR's API or a Monero node, Ravencoin from Blockbook, Insight or an explorer.
  - Block rewards: XMR from the network; RVN from the halving schedule (1,250 RVN since block 4.2M).
  - Electricity from the Mac's own power sensor (SMC `PSTR`). By default it charges only the extra watts above idle. You can also use whole-Mac power or manual estimates.
  - A per-period table (hour → year), break-even electricity price, and your share of each network's hashrate.
- **M5 Max presets**:
  - CPU: Auto, Full (18), Balanced (12, the default and best alongside GPU mining), Light (6), or Custom.
  - RandomX "fast" mode. Huge pages are off because macOS doesn't support them.
- **Rules**: pause on battery, pause under serious thermal pressure, mine only when idle for N minutes, keep the Mac awake while mining, start on launch, open at login.
- **Robust**:
  - Engines restart with back-off if they crash.
  - Settings changes restart only the engine they affect.
  - Leftover engine processes are cleaned up if the app ever crashes.
  - XMRig's API runs on localhost with a random token each run.
- **Settings** are stored in `~/Library/Application Support/MacDualMiner/settings.json`.

## Requirements

- Apple Silicon Mac (built and tuned for M5 Max; any M-series should work)
- macOS 15 Sequoia or later
- Xcode or the Command Line Tools: `xcode-select --install`
- A Monero wallet address and/or a Ravencoin wallet address (from a wallet you control)

## Build & install

```bash
git clone https://github.com/<you>/MacDualMiner.git
cd MacDualMiner
INSTALL=1 scripts/build-app.sh      # builds build/MacDualMiner.app and copies it to /Applications
```

The build script:

1. Compiles the app with SwiftPM in release mode.
2. Downloads the official **XMRig** macOS arm64 release (version pinned in the script) and **verifies its SHA-256** against XMRig's published `SHA256SUMS`.
3. Clones **kawpow-metal** at a pinned commit and applies `scripts/patch_kawpow.py`. The patch lets it find its shader and cache files from inside an app bundle and makes its output line-buffered. It then builds it.
4. Assembles `MacDualMiner.app` with both engines in `Contents/Resources/engines/`, ad-hoc code-signs it, and zips it.

Override the pinned versions with environment variables, e.g. `XMRIG_VERSION=6.26.0 KAWPOW_COMMIT=<sha> scripts/build-app.sh`.

Run the unit tests (earnings maths, parsers, config generation) with `swift test`.

## First run

1. Open **MacDualMiner** and go to **Settings (⌘,)**.
2. **CPU · Monero**: paste your XMR address (starts with `4` or `8`). The default pool is SupportXMR (`pool.supportxmr.com:443`, TLS, 0.6% fee).
3. **GPU · Ravencoin**: paste your RVN address (starts with `R`). The default pool is 2Miners (`rvn.2miners.com:6060`, 1% fee). kawpow-metal only speaks plain stratum, not TLS.
4. **Earnings**: set your electricity price per kWh from your bill, supply plus delivery. The default is $0.17.
5. Press **Start Mining**.

What to expect on first start:

- XMRig spends about 10–30 seconds building the 2 GB RandomX dataset.
- kawpow-metal builds the current epoch's light cache, then generates a multi-GB DAG on the GPU, which takes about a minute.
- The **idle baseline** for the power calculation is learned while the app is open and not mining. Leave it idle for a minute before your first start for the most accurate electricity numbers.

## How the earnings maths works

```
coins/sec = your_hashrate / hashes_per_block × block_reward × (1 − pool_fee) × (1 − dev_fee)
  Monero:    hashes_per_block = difficulty
  Ravencoin: hashes_per_block = difficulty × 2³²
USD/sec    = coins/sec × live_price
power/sec  = watts / 1000 / 3600 × $/kWh
net        = Σ USD − power      (then × 3,600 / 86,400 / 604,800 / 2,629,800 / 31,557,600)
```

These are expected values. Actual pool payouts vary with luck and difficulty swings, and pools hold coins until you reach their minimum payout.

## Notes & limitations

- **kawpow-metal** is a small, young project. Its README lists M1–M4, so M5 Max support is untested upstream. If the GPU side misbehaves, turn GPU mining off and the CPU side keeps going.
- Network-data endpoints are public third-party APIs and can change. If one breaks, the app tries the next. You can also set a custom Ravencoin stats URL or enter difficulty manually under Settings › Earnings.
- `NSAllowsArbitraryLoads` is enabled so the XMRig local API and plain-HTTP Monero node fallbacks work.
- Official XMRig builds donate a minimum of 1% of hashing time to the XMRig developers. The calculator accounts for this.

## Repository layout

```
Sources/MacDualMiner/
  MacDualMinerApp.swift      App, menu bar, crash clean-up
  MiningCoordinator.swift    Start/stop + pause rules, power allocation, earnings snapshot
  Engines/                   MinerProcess (child-process runner), XMRig + kawpow controllers
  Earnings/                  Calculator maths, live price / network-difficulty fetching
  System/                    SMC power sensor, battery, thermal, idle time
  Views/                     Dashboard, Earnings, Logs, Settings, menu bar
scripts/build-app.sh         Fetch + verify + build engines, assemble .app
scripts/patch_kawpow.py      Makes kawpow-metal bundle-friendly
.github/workflows/build.yml  CI: tests + app build on macOS; releases on v* tags
```

## License

MacDualMiner is MIT-licensed (see `LICENSE`). Bundled engines keep their own licenses: XMRig is GPL-3.0 and kawpow-metal is MIT. See `THIRD_PARTY_NOTICES.md`.
