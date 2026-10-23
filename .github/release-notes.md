MacDualMiner is a free, open-source **macOS crypto miner** for Apple Silicon Macs (M1–M5). It mines on the CPU and GPU, ranks coins by profit after electricity and switches automatically. [Full guide with screenshots](https://cryptominingonmacs.com/viewtopic.php?t=170).

## What's new in 0.4.5

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
5. On the **Profit Check** tab, click **Benchmark this Mac**, then press **Start Mining**.

**Requirements:** an Apple Silicon Mac (any M1–M5; not Intel) running macOS 15 Sequoia or later, with about 3 GB of free memory for CPU mining and 5–8 GB for GPU mining. Tuned for the M5 Max. For which engines have been tested on which chips, see the [compatibility table](https://github.com/becomethesolution/macdualminer#compatibility).

Bundled engines:

- XMRig, the official macOS arm64 release, SHA-256 verified at build time.
- kawpow-metal, built from source at a pinned commit.
- ethminer-m1, the release binary pinned by SHA-256.
- UselethMiner is optional: download it in-app from Settings › Engines.

Prefer to build it yourself? Clone the repo and run `INSTALL=1 scripts/build-app.sh`.

Full guide with screenshots and configuration: [MacDualMiner on cryptominingonmacs.com](https://cryptominingonmacs.com/viewtopic.php?t=170)
