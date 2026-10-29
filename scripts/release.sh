#!/bin/bash
# Build, notarize and publish a DockFolders release with its Sparkle update feed.
#
#   scripts/release.sh 0.2.0
#
# Version comes from the argument, the build number from the commit count, so nothing is committed;
# only the tag v<version> is pushed. One-time setup is in README.md ("Releasing").
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version, e.g. 0.2.0>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-dockfolders-notary}" # xcrun notarytool store-credentials <this name> …
SPARKLE_ACCOUNT=dockfolders                              # keychain item made by Sparkle's generate_keys
REPO=eric-silverman/dock-folders
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3"
[[ "$(git branch --show-current)" == main ]] || fail "release from main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree isn't clean"
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main isn't in sync with origin/main"
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "tag v$VERSION already exists"
[[ "$(gh repo view "$REPO" --json visibility -q .visibility)" == PUBLIC ]] ||
    fail "$REPO is private; Sparkle can't download updates from it"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
    fail "no notarytool keychain profile '$NOTARY_PROFILE' (see README, Releasing)"

BUILD=$(git rev-list --count HEAD)
OUT=build/release
APP="$OUT/dd/Build/Products/Release/DockFolders.app"
ZIP="$OUT/dist/DockFolders-$VERSION.zip"
SPARKLE_BIN="$OUT/dd/SourcePackages/artifacts/sparkle/Sparkle/bin"
rm -rf "$OUT" && mkdir -p "$OUT/dist"

echo "==> Testing"
xcodebuild -quiet -project DockFolders.xcodeproj -scheme DockFolders -derivedDataPath "$OUT/test" test

echo "==> Building $VERSION ($BUILD)"
xcodebuild -quiet -project DockFolders.xcodeproj -scheme DockFolders -configuration Release \
    -derivedDataPath "$OUT/dd" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" build
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -q "flags=.*runtime" || fail "hardened runtime missing"

echo "==> Notarizing (a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Signing the update feed"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "https://github.com/$REPO" -o "$OUT/dist/appcast.xml" "$OUT/dist"

echo "==> Publishing v$VERSION"
git tag -a "v$VERSION" -m "DockFolders $VERSION"
git push -q origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" "$OUT/dist/appcast.xml" --repo "$REPO" \
    --title "DockFolders $VERSION" --generate-notes
echo "Released: https://github.com/$REPO/releases/tag/v$VERSION"
