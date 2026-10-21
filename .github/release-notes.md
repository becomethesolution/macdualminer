MacDualMiner is a free, open-source **macOS crypto miner** for Apple Silicon Macs (M1–M5). It mines on the CPU and GPU, ranks coins by profit after electricity and switches automatically. [Full guide with screenshots](https://cryptominingonmacs.com/viewtopic.php?t=170).

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
