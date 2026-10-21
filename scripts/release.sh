#!/usr/bin/env bash
# Builds MacDualMiner on this Mac and publishes it as a GitHub release.
#
#   scripts/release.sh             build, copy to the builds folder, publish release v<VERSION>
#   INSTALL=1 scripts/release.sh   …and also install the new build to /Applications
#   DRY_RUN=1 scripts/release.sh   build and copy only; don't publish anything
#
# Every build is kept in "<builds folder>/<version>/". The builds folder is the "MacDualMiner Builds" folder this
# checkout sits in (e.g. ~/Desktop/BUILDZ/MacDualMiner Builds/MacDualMiner), otherwise
# ~/Desktop/BUILDZ/MacDualMiner Builds. Override with MACDUALMINER_BUILDS.
# Publishing uses the GitHub CLI (gh) if it's installed and signed in. Without it the script still builds
# and saves everything, and you publish the zip on the repo's Releases page in a browser.
#
# Releases are built locally rather than on GitHub Actions: GitHub has restricted Actions on this account.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="becomethesolution/macdualminer"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
PARENT="$(cd .. && pwd)"
if [[ -n "${MACDUALMINER_BUILDS:-}" ]]; then
  DEST_ROOT="$MACDUALMINER_BUILDS"
elif [[ "$(basename "$PARENT")" == "MacDualMiner Builds" ]]; then
  DEST_ROOT="$PARENT"
else
  DEST_ROOT="$HOME/Desktop/BUILDZ/MacDualMiner Builds"
fi
DEST="$DEST_ROOT/$VERSION"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nError: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
say "Checking the source"
[[ "$(uname -m)" == "arm64" ]] || die "build on an Apple Silicon Mac"
if [[ -n "$(git status --porcelain)" ]]; then
  die "you have uncommitted changes – commit or stash them first"
fi
git fetch --quiet origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  die "this checkout isn't the same as GitHub's main branch – run 'git pull' (and 'git push' if you made commits)"
fi

PUBLISH=1
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  PUBLISH=0
elif ! command -v gh >/dev/null || ! gh auth status >/dev/null 2>&1; then
  PUBLISH=0
  echo "GitHub CLI not installed or not signed in – will build and save only; publish the release in a browser."
fi
if [[ "$PUBLISH" == "1" ]]; then
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    die "$TAG is already released – bump VERSION to release a new build"
  fi
fi

# ---------------------------------------------------------------------------
# The unit tests need XCTest, which ships with Xcode but not with the Command Line Tools alone.
if [[ "$(xcode-select -p 2>/dev/null)" == *".app/"* ]]; then
  say "Running tests"
  swift test
else
  say "Skipping tests (they need Xcode; the Command Line Tools can still build the app)"
fi

say "Building MacDualMiner $VERSION"
INSTALL="${INSTALL:-0}" scripts/build-app.sh
ZIP="build/MacDualMiner-$VERSION.zip"
[[ -f "$ZIP" ]] || die "build didn't produce $ZIP"

# ---------------------------------------------------------------------------
say "Saving to $DEST"
mkdir -p "$DEST"
rm -rf "$DEST/MacDualMiner.app"
cp -R build/MacDualMiner.app "$DEST/"
cp "$ZIP" "$DEST/"
shasum -a 256 "$ZIP" | sed 's#build/##' > "$DEST/MacDualMiner-$VERSION.zip.sha256"
echo "Saved: $DEST"

if [[ "$PUBLISH" == "0" ]]; then
  say "Not published"
  echo "To publish: https://github.com/$REPO/releases/new?tag=$TAG"
  echo "Title: MacDualMiner $TAG – macOS Crypto Miner for Apple Silicon"
  echo "Attach: $DEST/MacDualMiner-$VERSION.zip   Notes: .github/release-notes.md"
  exit 0
fi

# ---------------------------------------------------------------------------
say "Publishing $TAG on GitHub"
gh release create "$TAG" "$ZIP" \
  --repo "$REPO" \
  --target "$(git rev-parse HEAD)" \
  --title "MacDualMiner $TAG – macOS Crypto Miner for Apple Silicon" \
  --notes-file .github/release-notes.md
echo "Released: https://github.com/$REPO/releases/tag/$TAG"
