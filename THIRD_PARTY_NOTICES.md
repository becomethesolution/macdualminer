# Third-party software

MacDualMiner's own source code is MIT-licensed. Built copies of the app bundle the following independent programs. They run as separate processes and keep their own licenses.

## XMRig

- Project: https://github.com/xmrig/xmrig
- License: GNU General Public License v3.0. The bundled copy of the license is in `Contents/Resources/licenses/XMRig-LICENSE.txt`.
- The bundled binary is the unmodified official macOS arm64 release. Source code for every release is available at https://github.com/xmrig/xmrig/releases.

## kawpow-metal

- Project: https://github.com/imperatormk/kawpow-metal
- License: MIT
- Built from source at the commit pinned in `scripts/build-app.sh`, with the small path and stdout changes in `scripts/patch_kawpow.py`.

## ethminer-m1

- Project: https://github.com/gyf304/ethminer-m1, an Apple Silicon build of https://github.com/ethereum-mining/ethminer
- License: GNU General Public License v3.0
- The bundled binary is the unmodified `v0.19.0-alpha.0-m1` release asset, pinned by SHA-256 in `scripts/build-app.sh`. Source code is available at https://github.com/gyf304/ethminer-m1.

## UselethMiner (not bundled)

- Project: https://github.com/Chainfire/UselethMiner, closed-source freeware by Chainfire with a 1% dev fee
- MacDualMiner doesn't redistribute it. When you click *Download & install* in Settings › Engines, the app fetches the official v0.23 macOS arm64 package from the author's GitHub release, checks its SHA-256 and unpacks it into `~/Library/Application Support/MacDualMiner/engines/useleth`.

## Data sources used at runtime

- Profit check: WhatToMine (network hashrate, block reward, BTC exchange rate and volume per coin)
- Prices: CoinGecko, Coinpaprika
- Reference hashrates: cryptominingonmacs.com
- Monero network: SupportXMR public API, Monero node JSON-RPC
- Ravencoin network: Ravencoin Blockbook / Insight APIs, Cryptoscope explorer

These are public third-party services and are not affiliated with MacDualMiner.
