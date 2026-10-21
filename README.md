# MacDualMiner

A lightweight native macOS app that mines on **both halves of an Apple Silicon chip at once**, with a **NiceHash-like style and interface**: one big Start button, live profitability, per-device controls and automatic switching to the most profitable coin. It runs on any M1–M5 Mac with macOS 15 or later and is tuned for the **M5 Max**. It runs four engines and **automatically picks the most profitable coin for each part of the chip**.

**Full guide with screenshots, setup and real M5 Max results:** [MacDualMiner on cryptominingonmacs.com](https://cryptominingonmacs.com/viewtopic.php?t=170)

| Engine | Part of the chip | Algorithm | Coins in the profit check | How it ships |
|---|---|---|---|---|
| [XMRig](https://github.com/xmrig/xmrig) | CPU | RandomX, GhostRider | Monero, Zephyr, QRL, Epic Cash, Etica, Raptoreum | Bundled (official release, SHA-256 verified) |
| [kawpow-metal](https://github.com/imperatormk/kawpow-metal) | GPU (Metal) | KawPow | Ravencoin, Quai, Neoxa, Neurai, Kerrigan | Bundled (built from a pinned commit) |
| [ethminer-m1](https://github.com/gyf304/ethminer-m1) | GPU (OpenCL) | Ethash | EthereumPoW, OctaSpace, QuarkChain | Bundled (release binary, pinned SHA-256) |
| [UselethMiner](https://github.com/Chainfire/UselethMiner) | CPU + GPU | Ethash | EthereumPoW | Optional in-app download (closed source, 1% fee) |

Engine choices and reference hashrates come from the Mac tests on [cryptominingonmacs.com](https://cryptominingonmacs.com/viewtopic.php?t=135). On the M5 Max those tests measured XMRig at 9.0 kH/s, ethminer-m1 at 41.6 MH/s and KawPow at 14.4 MH/s ([t=169](https://cryptominingonmacs.com/viewtopic.php?t=169)).

> **Reality check:** a Mac is not a profitable mining rig. Expect cents per day, and possibly a net loss once electricity is included. The earnings tab and the profit check are built to show that honestly. Mining also keeps the chip hot and fans busy for as long as it runs.

---

## Screenshots

Real numbers from a 2026 MacBook Pro 16" with an M5 Max (18-core CPU, 40-core GPU, 128 GB) at $0.17/kWh electricity. More guides and hashrate tests: [cryptominingonmacs.com](https://cryptominingonmacs.com).

**Dashboard.** Live profitability after electricity, both parts of the chip with their coin, engine, hashrate, watts and shares, and the power vs earnings chart. Here auto mode mines Monero on the CPU and has paused the GPU, because every coin it could mine there would lose money.

![MacDualMiner dashboard on an M5 Max mining Monero on the CPU with the GPU paused as unprofitable](docs/screenshots/macdualminer-dashboard-m5-max-mining-monero-cpu-gpu-paused.webp)

**Profit Check.** Every coin the bundled engines can mine, ranked by net USD per day, with its algorithm, engine, your hashrate (live, benchmarked on this Mac, or the cryptominingonmacs.com reference), coins mined per day, 24h trading volume and whether it's ready to mine.

![MacDualMiner profit check ranking coins by algorithm, engine and net USD per day on an M5 Max](docs/screenshots/macdualminer-profit-check-coins-algorithms-net-usd-per-day-m5-max.webp)

| | |
|---|---|
| ![MacDualMiner earnings projection in USD per hour, day, week, month and year](docs/screenshots/macdualminer-earnings-usd-per-hour-day-week-month-year.webp)<br>**Earnings.** Gross, electricity and net per hour, day, week, month and year, and how it's calculated. | ![MacDualMiner XMRig log with accepted shares and hashrate](docs/screenshots/macdualminer-logs-xmrig-randomx-accepted-shares.webp)<br>**Logs.** Each engine's own output: accepted shares and the hashrate the miner reports. |

![MacDualMiner menu bar menu with mining status and net earnings](docs/screenshots/macdualminer-menu-bar-status-earnings.webp)

**Menu bar.** Start or stop mining and watch earnings without opening the window.

### Settings

| | |
|---|---|
| ![MacDualMiner Coins & Wallets settings with a wallet per coin, pool choice and Kryptex account](docs/screenshots/macdualminer-settings-coins-wallets-pools-kryptex.webp)<br>**Coins & Wallets.** A wallet and pool per coin, or a Kryptex username. | ![MacDualMiner Switching settings: auto-switch, switch margin, minimum run time, liquidity filter and pausing unprofitable devices](docs/screenshots/macdualminer-settings-switching-auto-profit-switch-pause-unprofitable.webp)<br>**Switching.** Auto, recommend-only or manual, with a switch margin, minimum run time, trading-volume filter and pausing devices that would lose money. |
| ![MacDualMiner Engines settings: XMRig, kawpow-metal, ethminer-m1 and UselethMiner with separate 1–10 CPU and GPU power ratings](docs/screenshots/macdualminer-settings-engines-xmrig-kawpow-ethminer-cpu-gpu-power-rating.webp)<br>**Engines.** Turn the CPU, GPU and each engine on or off, and set separate 1–10 power ratings. | ![MacDualMiner Earnings settings: electricity price per kWh and measured power over idle](docs/screenshots/macdualminer-settings-earnings-electricity-price-power-measurement.webp)<br>**Earnings.** Your electricity price and how power is measured. |
| ![MacDualMiner Rules settings: pause on battery or thermal pressure, mine only while away, start at login](docs/screenshots/macdualminer-settings-rules-battery-thermal-idle-startup.webp)<br>**Rules.** Pause on battery or under thermal pressure, mine only while you're away, start at login. | ![MacDualMiner General settings: dark NiceHash-like look and GitHub update check](docs/screenshots/macdualminer-settings-general-github-update-check.webp)<br>**General.** The dark NiceHash-like look and the update check, which installs new GitHub releases after verifying them. |

Measured on the M5 Max: XMRig does about 7.6–7.9 kH/s with the CPU alone and 3–4 kH/s while the GPU also mines; kawpow-metal does about 42–46 MH/s with the GPU alone and 31–33 MH/s while the CPU also mines. Personal details (wallet address, Mac name, user folder) are blurred.

## Features

- **NiceHash-like interface:** a sidebar, a large Start/Stop button with live profitability, and one row per device (CPU and GPU) showing coin, algorithm, engine, hashrate, watts and shares, with an on/off switch and power slider for each. It also shows your Mac's own name, model and chip details, and has a dark look by default (switchable in Settings › General).
- **Power vs Earnings chart:** power draw against gross and net $/day over the last 1, 6 or 24 hours. A point is recorded every 30 seconds and the history is kept between launches; hover to read exact values.
- **Update check:** looks for new GitHub releases at launch and every 6 hours. *Install & Restart* downloads the release, checks it's the right app, version and code signature, swaps it in and relaunches.
- **Profit Check tab.** Every coin the engines can mine, with:
  - its **algorithm**
  - the **engine** and part of the chip it uses
  - **your hashrate** on that algorithm: live, benchmarked on this Mac, or the cryptominingonmacs.com reference for your chip
  - coins mined per day
  - **net USD/day** (gross minus electricity)
  - 24h trading volume
  - whether it's ready to mine

  Data comes from WhatToMine plus CoinGecko's BTC price. Coins too thinly traded to sell, coins with stale network data, and coins without a wallet or pool are flagged rather than picked.
- **Auto-switching.** The app picks the best CPU + GPU combination, or UselethMiner on both, and re-checks every 15 minutes. It switches only when the new plan is at least 10% better and the current coins have run for 20 minutes. All three thresholds are adjustable. The other modes are *Recommend*, which shows a "Switch" button, and *Manual*.
- **Benchmark this Mac.** Runs each installed engine for about 2 minutes on its best ready coin and records hashrate and power. Engines that mine steadily for 5 minutes also update their numbers automatically.
- **Power rating 1–10 for CPU and GPU separately.**
  - CPU: the level sets how many cores mine.
  - GPU: the level sets how much of each second the GPU engine runs; it's paused and resumed in short bursts.
  - The profit check scales its hashrate and power estimates to these levels.
- **Payouts:** set a wallet per coin, or a single Kryptex account that receives every coin on a Kryptex pool (auto-convert to BTC is available for all except QUAI).
- **Dashboard and menu bar:**
  - The dashboard shows each part of the chip: coin, algorithm, engine, hashrate, shares, pool, status and power slider.
  - The menu bar shows live net $/day and offers any better plan.
- **Earnings tab:** live USD per hour, day, week, month and year for whatever is running. Electricity comes from the Mac's own power sensor (SMC `PSTR`) and, by default, counts only the extra watts above idle.
- **Rules:** pause on battery, pause under serious thermal pressure, mine only when idle, keep the Mac awake while mining, start on launch, open at login.
- **Robust:**
  - Engines restart with back-off if they crash.
  - Only the engines a change affects are restarted.
  - Leftover engine processes are cleaned up after a crash.
  - Every bundled binary is checksum-verified at build time.

## Requirements

**To run the app**

- An Apple Silicon Mac: any M1, M2, M3, M4 or M5 chip. Intel Macs are not supported, because the app and all its engines are arm64-only.
- macOS 15 Sequoia or later. The KawPow GPU engine needs macOS 15.
- About 3 GB of free memory for CPU mining (XMRig's RandomX dataset is ~2.3 GB). GPU mining needs more: about 5 GB for KawPow and 7–8 GB for Ethash, because their DAGs grow over time.
- Wallet addresses for the coins you want to mine (from wallets you control), or a Kryptex account.
- An internet connection, for the pools, WhatToMine network data and coin prices.

**To build it yourself**

- Xcode, or just the Command Line Tools (`xcode-select --install`).

## Compatibility

| | M1 / M2 / M3 / M4 family | M5 | M5 Pro / M5 Max |
|---|---|---|---|
| App, dashboard, profit check | ✅ | ✅ | ✅ |
| XMRig – CPU (RandomX, GhostRider) | ✅ | ✅ | ✅ tested on M5 Max (9.0 kH/s) |
| kawpow-metal – GPU (KawPow) | ✅ listed by its author | ⚠️ not tested yet | ✅ runs on M5 Max |
| ethminer-m1 – GPU (Ethash) | ✅ | ✅ | ✅ tested on M5 Max (41.6 MH/s) |
| UselethMiner – CPU + GPU (Ethash) | ✅ tested up to M4 Max | ⚠️ not tested yet | ⚠️ not tested yet |
| Starting hashrates without a benchmark | M1 Ultra, M2, M2 Max, M3 Max, M3 Ultra, M4, M4 Max | – | M5 Max |

**What's tuned for M5:**

- CPU threads and the 1–10 power levels come from the detected 18-core layout (6 super + 12 performance).
- RandomX runs in fast mode, which suits the M5 Max's memory.
- The profit check starts from M5 Max hashrates measured on [cryptominingonmacs.com](https://cryptominingonmacs.com/viewtopic.php?t=169).

**What isn't:** the mining engines are general Apple Silicon builds. None of them is rewritten for M5-specific hardware such as the GPU's neural accelerators.

**Other Macs:** the app reads each Mac's own core counts, GPU and memory, so it works on any Apple Silicon Mac. On chips without a reference hashrate, click **Benchmark this Mac** on the Profit Check tab and the profit check uses your own numbers.

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

1. Open **MacDualMiner** and go to **Settings (⌘,) › Coins & Wallets**.
2. For each coin you want to be eligible, paste a wallet address. Alternatively, enter a **Kryptex username** once, and every coin on a Kryptex pool (Monero, Zephyr, EthereumPoW, Quai) becomes eligible.
3. Coins without a preset pool (QRL, Neoxa, Neurai, …) need a custom pool, entered under the coin.
4. **Settings › Earnings**: set your electricity price per kWh from your bill.
5. Optional: under **Settings › Engines**, click *Download & install* for UselethMiner.
6. Open the **Profit Check** tab and click **Benchmark this Mac** so the ranking uses this Mac's real hashrates. Until then it uses the cryptominingonmacs.com result for your chip.
7. Press **Start Mining**. In Auto mode the app runs the best plan and keeps re-checking.

What to expect on first start:

- XMRig spends about 10–30 seconds building its 2 GB RandomX dataset.
- GPU engines build a multi-GB DAG first (about a minute).
- UselethMiner's first DAG load can take a few minutes.

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
  MiningCoordinator.swift    Start/stop, auto-switching, pause rules, benchmarks, power allocation, earnings
  Model/CoinCatalog.swift    Coins per algorithm, engines, pool presets
  Model/ReferenceHashrates   cryptominingonmacs.com results per chip
  Engines/                   MinerProcess (runner + GPU duty cycle), XMRig, kawpow, ethminer, UselethMiner, installer
  Earnings/                  Earnings maths, WhatToMine data, profit planner
  System/                    SMC power sensor, battery, thermal, idle time
  Views/                     Dashboard, Profit Check, Earnings, Logs, Settings, menu bar
scripts/build-app.sh         Fetch + verify + build engines, assemble .app
scripts/patch_kawpow.py      Makes kawpow-metal bundle-friendly
.github/workflows/build.yml  CI: tests + app build on macOS; releases on v* tags
```

## More guides

Mac mining results, engine tests and guides: **[cryptominingonmacs.com](https://cryptominingonmacs.com)**.

MacDualMiner is an independent project. It is not affiliated with or endorsed by NiceHash; the name is used only to describe the style of the interface.

## License

MacDualMiner is MIT-licensed (see `LICENSE`). Bundled engines keep their own licenses: XMRig is GPL-3.0 and kawpow-metal is MIT. See `THIRD_PARTY_NOTICES.md`.
