#!/usr/bin/env bash
# Build a signed Release Voce.app and install it to /Applications.
#
# Because every build is signed with the same identity and bundle ID,
# macOS treats each install as an update of the same app: Accessibility
# and Microphone grants persist instead of being re-requested.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Release/Voce.app"
DEST="/Applications/Voce.app"

xcodegen generate

"$XCODEBUILD" \
  -project Voce.xcodeproj \
  -scheme Voce \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build | tail -2

echo "— Signature —"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "Identifier|Authority" || true

# Replace the installed copy in place; same signature ⇒ TCC grants persist.
pkill -x Voce 2>/dev/null || true
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "Installed $DEST"
open "$DEST"
