#!/bin/bash
# Build, notarize and publish a DockFolders release with its Sparkle update feed.
#
#   scripts/release.sh 0.2.0
#
# Version comes from the argument, the build number from the commit count, so nothing is committed;
# the release creates the tag v<version>. One-time setup is in README.md ("Releasing").
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
[[ -z "$(git ls-remote --tags origin "v$VERSION")" ]] || fail "tag v$VERSION already exists on origin"
[[ "$(gh repo view "$REPO" --json visibility -q .visibility)" == PUBLIC ]] ||
    fail "$REPO is private; Sparkle can't download updates from it"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
    fail "no notarytool keychain profile '$NOTARY_PROFILE' (see README, Releasing)"

BUILD=$(git rev-list --count HEAD)
OUT=$(mktemp -d)/release # outside Dropbox, which adds xattrs that break codesign
APP="$OUT/dd/Build/Products/Release/DockFolders.app"
ZIP="$OUT/dist/DockFolders-$VERSION.zip"
SPARKLE_BIN="$OUT/dd/SourcePackages/artifacts/sparkle/Sparkle/bin"
mkdir -p "$OUT/dist"

echo "==> Testing"
xcodebuild -quiet -project DockFolders.xcodeproj -scheme DockFolders -derivedDataPath "$OUT/test" test

echo "==> Building $VERSION ($BUILD)"
xcodebuild -quiet -project DockFolders.xcodeproj -scheme DockFolders -configuration Release \
    -derivedDataPath "$OUT/dd" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" build
# Xcode signs Sparkle.framework but leaves its helpers ad hoc, which notarization rejects. Re-sign them
# inside-out with our certificate (Sparkle's documented order), then reseal the app.
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)/\1/p')
[[ -n "$IDENTITY" ]] || fail "$APP isn't signed with a Developer ID certificate"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for item in Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc \
            Versions/B/Autoupdate Versions/B/Updater.app ""; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements -s "$IDENTITY" "$SPARKLE/$item"
done
codesign --force --options runtime --timestamp --preserve-metadata=entitlements -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -q "flags=.*runtime" || fail "hardened runtime missing"
! codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow || fail "get-task-allow entitlement present"

echo "==> Notarizing (a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP" # what Gatekeeper will say on users' Macs
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Signing the update feed"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "https://github.com/$REPO" -o "$OUT/dist/appcast.xml" "$OUT/dist"

echo "==> Publishing v$VERSION"
# gh creates the tag with the release, so a failure here leaves no stray tag and the script can be re-run.
gh release create "v$VERSION" "$ZIP" "$OUT/dist/appcast.xml" --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "DockFolders $VERSION" --generate-notes
echo "Released: https://github.com/$REPO/releases/tag/v$VERSION"
