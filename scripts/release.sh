#!/usr/bin/env bash
# Builds MacDualMiner on this Mac and publishes it as a GitHub release.
#
#   scripts/release.sh             build, copy to the builds folder, publish release v<VERSION>
#   INSTALL=1 scripts/release.sh   …and also install the new build to /Applications
#   DRY_RUN=1 scripts/release.sh   build and copy only; don't publish anything
#
# Every build is kept in "~/Desktop/MacDualMiner Builds/<version>/" (override with MACDUALMINER_BUILDS).
# Publishing needs the GitHub CLI, signed in once:  brew install gh && gh auth login
#
# Releases are built locally rather than on GitHub Actions: GitHub has restricted Actions on this account.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="becomethesolution/macdualminer"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
DEST_ROOT="${MACDUALMINER_BUILDS:-$HOME/Desktop/MacDualMiner Builds}"
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

if [[ "${DRY_RUN:-0}" != "1" ]]; then
  command -v gh >/dev/null || die "the GitHub CLI isn't installed – run: brew install gh && gh auth login"
  gh auth status >/dev/null 2>&1 || die "the GitHub CLI isn't signed in – run: gh auth login"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    die "$TAG is already released – bump VERSION to release a new build"
  fi
fi

# ---------------------------------------------------------------------------
say "Running tests"
swift test

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

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  say "Dry run – nothing published"
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
