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
   - Add your Monero and/or Ravencoin wallet address.
   - Set your electricity price per kWh.
5. Press **Start Mining**.

**Requirements:** Apple Silicon Mac, macOS 15 or later. Tuned for the M5 Max.

Bundled engines:

- XMRig, the official macOS arm64 release, SHA-256 verified at build time.
- kawpow-metal, built from source at a pinned commit.

Prefer to build it yourself? Clone the repo and run `INSTALL=1 scripts/build-app.sh`.
