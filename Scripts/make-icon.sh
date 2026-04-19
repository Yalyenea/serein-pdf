#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from Resources/AppIcon.png
# Requires: sips, iconutil (both bundled with macOS)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$PROJECT_ROOT/Resources/AppIcon.png"
ICONSET_DIR="$PROJECT_ROOT/Resources/AppIcon.iconset"
OUTPUT="$PROJECT_ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE" ]]; then
    echo "error: missing source icon at $SOURCE" >&2
    exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

declare -a SIZES=(
    "16 icon_16x16.png"
    "32 icon_16x16@2x.png"
    "32 icon_32x32.png"
    "64 icon_32x32@2x.png"
    "128 icon_128x128.png"
    "256 icon_128x128@2x.png"
    "256 icon_256x256.png"
    "512 icon_256x256@2x.png"
    "512 icon_512x512.png"
    "1024 icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    size="${entry%% *}"
    name="${entry#* }"
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET_DIR/$name" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT"
rm -rf "$ICONSET_DIR"
echo "built: $OUTPUT"
