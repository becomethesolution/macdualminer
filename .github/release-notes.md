MacDualMiner is a free, open-source **macOS crypto miner** for Apple Silicon Macs (M1–M5). It mines on the CPU and GPU, ranks coins by profit after electricity and switches automatically. [Full guide with screenshots](https://cryptominingonmacs.com/viewtopic.php?t=170).

## What's new in 0.5.0

- **Setup assistant.** The first time you open the app it walks you through three steps: your electricity price, where to get paid (any wallet such as Trust Wallet via unMineable, your own coin wallets, or a Kryptex account), and the benchmark. Settings › General › Setup assistant opens it again.
- **Pool balance on the Dashboard.** A new panel shows the unpaid balance waiting for you at Kryptex, unMineable, SupportXMR and 2Miners, with progress towards each pool's payout threshold – proof your mining is landing somewhere. Updated every 10 minutes from the pools' public pages; nothing to sign in to.
- **What each chip earns.** Profit Check's *Best option* now shows each chip's own net per day. When one chip loses money on its best coin, it says how much and what keeping that chip idle would save, with a checkbox to do that. Start still mines every chip you start, as before.
- **Benchmark your way.** The menu next to *Benchmark this Mac* chooses which engines it runs, and right-clicking a coin on Profit Check benchmarks just that one (unmeasured coins also get a *Benchmark* link). *Skip* from 0.4.11 still skips the engine being measured.
- **Live UselethMiner stats.** UselethMiner held back its output and the app saw it in one-minute bursts; it now runs in a terminal-style session, so hashrate updates every second. Its share count now counts the shares it submits – UselethMiner doesn't report whether the pool accepted them.

## Also in 0.4.11

- **UselethMiner fixed.** Installed from the app, UselethMiner quit at start with "dlopen … libpycfethash_armv8af.dylib (no such file)": it only runs from /usr/local/uselethminer (its compiled code loads its libraries from there, and macOS won't let it look elsewhere). **Settings › Engines › Download & install** now installs the author's package there with Apple's installer, after checking its SHA-256, so macOS asks for your password once. The old copy in the app's folder is removed automatically – if you had installed UselethMiner before, click Download & install again. Remove also asks for your password.
- **Skip a benchmark step.** While Benchmark this Mac is running, Profit Check shows **Skip <engine>** next to Cancel: it stops the engine being tested and moves on to the next one. Useful for UselethMiner, whose first run spends several minutes building its DAG. A skipped engine keeps its earlier result, if it had one.
- Setup messages now read "Needs your ETHW wallet" / "Needs your DOGE payout address".

## Also in 0.4.10

- **Clearer unMineable setup on the Monero page.** When Monero's pool is set to unMineable, the Monero wallet field is replaced by **Pay me in** and your payout address (for example your Dogecoin address from Trust Wallet), so the page shows the one address that actually gets paid. Your Monero wallet stays saved and comes back if you switch to another pool. It's the same setting as under Payouts & worker.
- **Payout address check.** The payout address is checked against the coin you picked (Dogecoin, Litecoin, Bitcoin, Tron, Solana and others), so pasting an address for the wrong coin shows a warning right away.
- Pool menus now show just the pool name and fee, with the server address underneath, so long names aren't cut off.

## Also in 0.4.9

- **Get paid into Trust Wallet (or any wallet) in another coin.** Settings › Coins & Wallets › Payouts & worker has a new **unMineable** option: your Mac keeps mining Monero on the CPU, and unMineable pays you in Dogecoin, Litecoin, Bitcoin, Tron, Solana and more, to the address you enter. No Monero wallet needed. Earnings are the same as Monero, less unMineable's fee of about 1%.
- **Reorganized Coins & Wallets.** A compact list on the left, grouped into CPU, GPU and *More coins (bring your own pool)*, with a ready / needs-setup dot and each coin's current net per day, sorted best first, plus an All / Ready / Needs setup filter. The selected coin's wallet and pool are on the right. Worker name, Kryptex and unMineable are under **Payouts & worker** at the top.
- The **Set it up in Coins & Wallets** link under a device now opens that coin directly. The Settings window is a little wider to fit the new layout.

## Also in 0.4.8

- **Auto-switch on/off per chip.** The Auto-switching panel on the Dashboard has a **CPU auto-switch** and a **GPU auto-switch** toggle. Turning one off keeps that chip on the coin it's mining now; turning it on lets it switch to the best coin again. It's the same setting as picking a coin (or Auto) in the chip's coin menu, so the two always match.

## Also in 0.4.7

- **Fixes from a full review of the 0.4.x changes:**
  - The activity log no longer repeats "Paused – every ready coin loses money" every few seconds when no coin is set up yet; it now says once that no coin is ready and to add a wallet or pool.
  - Starting just the CPU or GPU always gives it a coin right away, even when UselethMiner (CPU + GPU) looks best overall. Starting either side of a UselethMiner pick starts both.
  - A coin you pick yourself keeps mining when its market data is briefly stale or its trading volume dips; only a missing wallet, pool or engine stops it.
  - In manual mode, picking a CPU-only or GPU-only coin after UselethMiner now takes effect.
  - Starting or stopping one chip no longer restarts the other chip's minimum run time, and Start/Stop pressed during a benchmark is kept.
  - The menu bar no longer shows warnings for a chip you didn't start.
- **Clearer Dashboard:** a stopped chip shows the coin it would mine; the coin menu shows its algorithm, engine and Auto / your pick underneath; the loss note doesn't promise auto-switching for a coin you picked.
- **Small fixes:** no more "−$0.0000"; the Logs tab says how to get output; the About box links to GitHub; people upgrading from 0.4.4 or earlier get a one-time note in the activity log that Start now always mines.


## Also in 0.4.6

- **Pick a coin for each chip.** The coin under the CPU and GPU on the Dashboard is now a menu: **Auto – best coin**, or any coin that part of the chip can mine, with its current net per day. Picking a coin pins only that chip; the other keeps auto-switching. Coins that aren't ready show why (for example, a missing wallet), with a shortcut to add one.
- **Mine in Profit Check** now pins that coin the same way instead of switching the whole app to manual mode.
- **Tari (XTM) on the CPU.** Tari's own RandomX chain can now be mined with XMRig on Kryptex's Tari pool (needs a Tari wallet). It uses your RandomX benchmark, so no extra benchmarking is needed.
- The auto-switching log now says "least costly option" when nothing is profitable, instead of "best profitable option".

## Also in 0.4.5

- **Start always mines.** Start All Miners now starts mining right away, even when nothing is profitable at your electricity price: auto mode picks the least costly coin. A note under the CPU or GPU row says so ("As of current calculations, … won't be profitable at $x/kWh – about −$y/day") and points out any coin that would pay if you add a wallet. No pop-ups. If you'd rather keep a device idle until a coin is profitable, turn on Settings › Switching › *Keep a started device idle when every coin on it would lose money*.
- **Start and stop the CPU and GPU separately.** Each device row on the Dashboard has its own Start/Stop button. The main button is now **Start All Miners / Stop All Miners**.
- **Chip and battery temperature** under Power & Thermals, in °F or °C (Settings › General › Units; defaults to your region).
- **Mining at your own risk.** A dismissible notice on the Dashboard explains that MacDualMiner comes without warranty and that sustained mining adds heat and wear, especially to laptop batteries. The same note is in the About box, with tips in Settings › Rules.

## Also in 0.4.4

- **Help › Send Feedback…** opens a new GitHub issue with your MacDualMiner version, Mac model, chip and macOS version already filled in. You just describe the problem; nothing is sent until you submit it on GitHub, and your Mac's name isn't included.
- **Help › Share Your Hashrate…** does the same for hashrate reports, which help improve the reference numbers for each chip.
- The same two links are in Settings › General › Help & community.

## Also in 0.4.3

- **Help › Check for Updates…** checks GitHub right away and tells you the result: up to date, or a new version with *Install & Restart* and *Release Notes* buttons.

## Also in 0.4.2

- **Help and community links.** The Help menu now has the MacDualMiner guide, the [CryptoMiningOnMacs.com](https://cryptominingonmacs.com/) community and a link to report issues. The same links are in Settings › General › Help & community, and in a small "Community" link at the bottom of the sidebar.
- **Clickable reference hashrates.** In Profit Check, hashrates marked *cryptominingonmacs.com* now open the test results they come from.
- **About box** now shows the copyright, license and a link to CryptoMiningOnMacs.com.
- **License change.** From this version on, MacDualMiner is licensed under the GNU General Public License v3.0 (0.4.1 and earlier stay MIT). "MacDualMiner" and its icon are trademarks of Become the Solution, LLC; forks need their own name and icon. See [TRADEMARKS.md](https://github.com/becomethesolution/macdualminer/blob/main/TRADEMARKS.md).

## Install

1. Download **MacDualMiner-x.y.z.zip** below and unzip it.
2. Drag **MacDualMiner.app** into **Applications**.
3. Open it. The app is ad-hoc signed, not notarized by Apple, so the first time macOS will say it can't verify the developer. Do one of the following:
   - Go to **System Settings › Privacy & Security**, scroll to the message about MacDualMiner and click **Open Anyway**.
   - Or run this once in Terminal:

     ```
     xattr -dr com.apple.quarantine /Applications/MacDualMiner.app
     ```
4. Open **Settings (⌘,)**:
   - Under **Coins & Wallets**, add a wallet for each coin you want to mine, or a Kryptex username.
   - Under **Earnings**, set your electricity price per kWh.
5. On the **Profit Check** tab, click **Benchmark this Mac**, then press **Start All Miners**.

**Requirements:** an Apple Silicon Mac (any M1–M5; not Intel) running macOS 15 Sequoia or later, with about 3 GB of free memory for CPU mining and 5–8 GB for GPU mining. Tuned for the M5 Max. For which engines have been tested on which chips, see the [compatibility table](https://github.com/becomethesolution/macdualminer#compatibility).

Bundled engines:

- XMRig, the official macOS arm64 release, SHA-256 verified at build time.
- kawpow-metal, built from source at a pinned commit.
- ethminer-m1, the release binary pinned by SHA-256.
- UselethMiner is optional: download it in-app from Settings › Engines.

Prefer to build it yourself? Clone the repo and run `INSTALL=1 scripts/build-app.sh`.

Full guide with screenshots and configuration: [MacDualMiner on cryptominingonmacs.com](https://cryptominingonmacs.com/viewtopic.php?t=170)
