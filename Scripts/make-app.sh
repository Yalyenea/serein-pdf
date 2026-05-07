#!/usr/bin/env bash
# Build a release Serein.app bundle under build/Serein.app
# Usage: Scripts/make-app.sh [output-dir]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build}"
APP_NAME="Serein"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

cd "$PROJECT_ROOT"

echo "==> swift build -c release"
swift build -c release --disable-sandbox

BIN_PATH="$(swift build -c release --disable-sandbox --show-bin-path)"
EXECUTABLE="$BIN_PATH/$APP_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "error: built executable not found at $EXECUTABLE" >&2
    exit 1
fi

echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

ICON_SRC="$PROJECT_ROOT/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
    echo "==> generating AppIcon.icns"
    "$PROJECT_ROOT/Scripts/make-icon.sh"
fi
cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

if [[ -d "$PROJECT_ROOT/Resources/Assets.xcassets" ]]; then
    echo "==> compiling Assets.xcassets"
    actool --compile "$APP_BUNDLE/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 "$PROJECT_ROOT/Resources/Assets.xcassets" >/dev/null
fi

# Ad-hoc sign so Gatekeeper / Launch Services accept the bundle locally.
codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null

echo "built: $APP_BUNDLE"
