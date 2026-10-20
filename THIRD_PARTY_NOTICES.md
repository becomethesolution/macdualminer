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

## Data sources used at runtime

- Prices: CoinGecko, Coinpaprika
- Monero network: SupportXMR public API, Monero node JSON-RPC
- Ravencoin network: Ravencoin Blockbook / Insight APIs, Cryptoscope explorer

These are public third-party services and are not affiliated with MacDualMiner.
