#!/usr/bin/env bash
# Builds MacDualMiner.app with both mining engines bundled inside.
#
#   scripts/build-app.sh            → build/MacDualMiner.app (+ build/MacDualMiner-<version>.zip)
#   INSTALL=1 scripts/build-app.sh  → also copies the app to /Applications
#
# Requirements: Apple Silicon Mac, macOS 15+, Xcode or Xcode Command Line Tools (swift, git, python3).
set -euo pipefail

XMRIG_VERSION="${XMRIG_VERSION:-6.26.0}"
KAWPOW_REPO="${KAWPOW_REPO:-https://github.com/imperatormk/kawpow-metal.git}"
KAWPOW_COMMIT="${KAWPOW_COMMIT:-e9f504773b8613188d0b303b4533504d866be47e}"
# ethminer-m1 (GPL-3) publishes no checksums, so we pin the SHA-256 of the release binary.
ETHMINER_URL="${ETHMINER_URL:-https://github.com/gyf304/ethminer-m1/releases/download/v0.19.0-alpha.0-m1/ethminer-m1}"
ETHMINER_SHA256="${ETHMINER_SHA256:-f110b385931ea4a3d594e660b3f0db2c08705fe94bc3a2280be218cd08f43c6f}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
CACHE="$BUILD/cache"
APP="$BUILD/MacDualMiner.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "build on macOS"
[[ "$(uname -m)" == "arm64" ]] || echo "note: building on $(uname -m) – cross-compiling the arm64 app (it runs on Apple Silicon only)"
command -v swift >/dev/null || die "swift not found – run: xcode-select --install"
command -v python3 >/dev/null || die "python3 not found – run: xcode-select --install"
mkdir -p "$CACHE"

# ---------------------------------------------------------------------------
say "1/6  Building MacDualMiner $VERSION (release)"
swift build --package-path "$ROOT" -c release --arch arm64 --product MacDualMiner
APP_BIN="$(swift build --package-path "$ROOT" -c release --arch arm64 --show-bin-path)/MacDualMiner"

# ---------------------------------------------------------------------------
say "2/6  Fetching XMRig $XMRIG_VERSION (macOS arm64) and verifying its checksum"
XMRIG_TGZ="xmrig-$XMRIG_VERSION-macos-arm64.tar.gz"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION"
[[ -f "$CACHE/$XMRIG_TGZ" ]] || curl -fL --retry 3 -o "$CACHE/$XMRIG_TGZ" "$XMRIG_URL/$XMRIG_TGZ"
curl -fsSL --retry 3 -o "$CACHE/xmrig-SHA256SUMS-$XMRIG_VERSION" "$XMRIG_URL/SHA256SUMS"
# Lines look like "<sha256> *<file>" (the * marks binary mode) or "<sha256>  <file>".
EXPECTED="$(awk -v f="$XMRIG_TGZ" '{ n = $2; sub(/^\*/, "", n); if (n == f) print $1 }' "$CACHE/xmrig-SHA256SUMS-$XMRIG_VERSION")"
[[ -n "$EXPECTED" ]] || die "no checksum for $XMRIG_TGZ in XMRig's SHA256SUMS"
ACTUAL="$(shasum -a 256 "$CACHE/$XMRIG_TGZ" | awk '{print $1}')"
[[ "$EXPECTED" == "$ACTUAL" ]] || { rm -f "$CACHE/$XMRIG_TGZ"; die "XMRig checksum mismatch (expected $EXPECTED, got $ACTUAL)"; }
echo "checksum OK: $ACTUAL"
rm -rf "$BUILD/xmrig"; mkdir -p "$BUILD/xmrig"
tar -xzf "$CACHE/$XMRIG_TGZ" -C "$BUILD/xmrig"
XMRIG_BIN="$(find "$BUILD/xmrig" -type f -name xmrig -perm -u+x | head -1)"
[[ -n "$XMRIG_BIN" ]] || die "xmrig binary not found in archive"

# ---------------------------------------------------------------------------
say "3/6  Building kawpow-metal @ ${KAWPOW_COMMIT:0:7} (Metal GPU miner)"
KP="$BUILD/kawpow-src"
if [[ ! -d "$KP/.git" ]]; then
  git clone --quiet "$KAWPOW_REPO" "$KP"
fi
git -C "$KP" fetch --quiet origin
git -C "$KP" checkout --quiet --force "$KAWPOW_COMMIT"
git -C "$KP" clean -fdq -e .build
python3 "$ROOT/scripts/patch_kawpow.py" "$KP"
swift build --package-path "$KP" -c release --arch arm64
KP_BIN="$(swift build --package-path "$KP" -c release --arch arm64 --show-bin-path)/kawpow-metal"
[[ -x "$KP_BIN" ]] || die "kawpow-metal build failed"

# ---------------------------------------------------------------------------
say "4/6  Fetching ethminer-m1 (OpenCL Ethash miner) and verifying its checksum"
[[ -f "$CACHE/ethminer-m1" ]] || curl -fL --retry 3 -o "$CACHE/ethminer-m1" "$ETHMINER_URL"
ACTUAL="$(shasum -a 256 "$CACHE/ethminer-m1" | awk '{print $1}')"
[[ "$ACTUAL" == "$ETHMINER_SHA256" ]] || { rm -f "$CACHE/ethminer-m1"; die "ethminer-m1 checksum mismatch (expected $ETHMINER_SHA256, got $ACTUAL)"; }
echo "checksum OK: $ACTUAL"

# ---------------------------------------------------------------------------
say "5/6  Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engines/xmrig" "$APP/Contents/Resources/engines/kawpow" \
         "$APP/Contents/Resources/engines/ethminer" "$APP/Contents/Resources/licenses"
cp "$APP_BIN" "$APP/Contents/MacOS/MacDualMiner"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cp "$XMRIG_BIN" "$APP/Contents/Resources/engines/xmrig/xmrig"
cp "$KP_BIN" "$APP/Contents/Resources/engines/kawpow/kawpow-metal"
cp "$KP/Sources/KawpowShader.metal.template" "$APP/Contents/Resources/engines/kawpow/"
cp "$CACHE/ethminer-m1" "$APP/Contents/Resources/engines/ethminer/ethminer-m1"
chmod +x "$APP/Contents/Resources/engines/xmrig/xmrig" "$APP/Contents/Resources/engines/kawpow/kawpow-metal" \
         "$APP/Contents/Resources/engines/ethminer/ethminer-m1"

cp "$ROOT/LICENSE" "$APP/Contents/Resources/licenses/MacDualMiner-LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/licenses/"
XMRIG_LICENSE="$(find "$BUILD/xmrig" -maxdepth 2 -iname 'LICENSE*' | head -1 || true)"
[[ -n "$XMRIG_LICENSE" ]] && cp "$XMRIG_LICENSE" "$APP/Contents/Resources/licenses/XMRig-LICENSE.txt"

# Ad-hoc sign: inner executables first, then the bundle.
codesign --force --sign - "$APP/Contents/Resources/engines/xmrig/xmrig"
codesign --force --sign - "$APP/Contents/Resources/engines/kawpow/kawpow-metal"
codesign --force --sign - "$APP/Contents/Resources/engines/ethminer/ethminer-m1"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# ---------------------------------------------------------------------------
say "6/6  Packaging"
ZIP="$BUILD/MacDualMiner-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "App: $APP"
echo "Zip: $ZIP"

if [[ "${INSTALL:-0}" == "1" ]]; then
  osascript -e 'tell application "MacDualMiner" to quit' >/dev/null 2>&1 || true
  rm -rf /Applications/MacDualMiner.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/MacDualMiner.app"
fi
