#!/usr/bin/env bash
# Package a signed Release Voce.app into a drag-to-install DMG.
#
#   scripts/package.sh [version]     # default 0.1.0
#
# Output: dist/Voce-<version>.dmg. The app inside is signed with the same
# stable identity as local installs, so installing an update over
# /Applications/Voce.app keeps existing Accessibility/Microphone grants.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Release/Voce.app"
DMG="dist/Voce-$VERSION.dmg"

xcodegen generate

"$XCODEBUILD" \
  -project Voce.xcodeproj \
  -scheme Voce \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build | tail -2

echo "— Verifying signature —"
codesign --verify --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "Identifier|Authority"

echo "— Building DMG —"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Voce.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create \
  -volname "Voce $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO -ov \
  "$DMG" >/dev/null

echo "Packaged: $DMG"
echo "Version:  $VERSION (build $BUILD_NUMBER)"
