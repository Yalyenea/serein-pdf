#!/usr/bin/env bash
# Package the built Serein.app into a DMG under build/Serein-<version>.dmg
# Usage: Scripts/make-dmg.sh [output-dir]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build}"
APP_NAME="Serein"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: $APP_BUNDLE not found. Run 'just build' first." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"

STAGING_DIR="$(mktemp -d -t serein-dmg)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "==> staging $APP_NAME.app at $STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
echo "==> creating $DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null

echo "built: $DMG_PATH"
