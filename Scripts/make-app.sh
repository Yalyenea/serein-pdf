#!/usr/bin/env bash
# Build a release SlatePDF.app bundle under build/SlatePDF.app
# Usage: Scripts/make-app.sh [output-dir]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build}"
APP_NAME="SlatePDF"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

cd "$PROJECT_ROOT"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
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

# Ad-hoc sign so Gatekeeper / Launch Services accept the bundle locally.
codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null

echo "built: $APP_BUNDLE"
