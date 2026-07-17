#!/usr/bin/env bash
# End-to-end verification for GitHub-based auto-update (private repo needs token).
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

TOKEN="${SEREIN_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  if command -v gh >/dev/null 2>&1; then
    TOKEN="$(gh auth token 2>/dev/null || true)"
  fi
fi

if [[ -z "$TOKEN" ]]; then
  echo "error: set SEREIN_GITHUB_TOKEN or GITHUB_TOKEN (or gh auth login) for private releases" >&2
  exit 1
fi

export SEREIN_GITHUB_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

echo "==> unit tests (AppUpdateService + config)"
swift test --disable-sandbox --filter AppUpdateServiceTests
swift test --disable-sandbox --filter AppConfigurationTests

echo "==> live GitHub latest release"
API_JSON="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/Yalyenea/serein-pdf/releases/latest)"

TAG="$(python3 - <<'PY' "$API_JSON"
import json,sys
print(json.loads(sys.argv[1])["tag_name"])
PY
)"
ASSET_NAME="$(python3 - <<'PY' "$API_JSON"
import json,sys
assets=json.loads(sys.argv[1])["assets"]
dmg=[a for a in assets if a["name"].startswith("Serein-") and a["name"].endswith(".dmg")]
assert dmg, "no Serein-*.dmg asset"
print(sorted(dmg, key=lambda a: a["name"])[-1]["name"])
PY
)"
ASSET_ID="$(python3 - <<'PY' "$API_JSON"
import json,sys
assets=json.loads(sys.argv[1])["assets"]
dmg=[a for a in assets if a["name"].startswith("Serein-") and a["name"].endswith(".dmg")]
print(sorted(dmg, key=lambda a: a["name"])[-1]["id"])
PY
)"

echo "latest tag: $TAG"
echo "asset: $ASSET_NAME ($ASSET_ID)"

WORK="$(mktemp -d -t serein-update-verify)"
trap 'rm -rf "$WORK"' EXIT

echo "==> download release asset via API"
curl -fsSL \
  -H "Accept: application/octet-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/Yalyenea/serein-pdf/releases/assets/$ASSET_ID" \
  -o "$WORK/$ASSET_NAME"

file "$WORK/$ASSET_NAME" | grep -qi 'disk image\|zlib\|data' || {
  echo "error: downloaded file does not look like a DMG" >&2
  ls -la "$WORK"
  exit 1
}

echo "==> mount and confirm Serein.app"
MOUNT="$WORK/mount"
mkdir -p "$MOUNT"
hdiutil attach "$WORK/$ASSET_NAME" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
trap 'hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
test -d "$MOUNT/Serein.app"
test -x "$MOUNT/Serein.app/Contents/MacOS/Serein"
REMOTE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT/Serein.app/Contents/Info.plist")"
echo "remote app version: $REMOTE_VERSION"
hdiutil detach "$MOUNT" -force >/dev/null
rmdir "$MOUNT" 2>/dev/null || true

echo "==> local install swap dry-run (temp destination)"
DEST_ROOT="$WORK/Applications"
mkdir -p "$DEST_ROOT/Serein.app/Contents"
echo old > "$DEST_ROOT/Serein.app/Contents/marker.txt"
# Re-attach for install copy
mkdir -p "$MOUNT"
hdiutil attach "$WORK/$ASSET_NAME" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
rm -rf "$DEST_ROOT/Serein.app"
cp -R "$MOUNT/Serein.app" "$DEST_ROOT/Serein.app"
hdiutil detach "$MOUNT" -force >/dev/null
test -x "$DEST_ROOT/Serein.app/Contents/MacOS/Serein"
INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST_ROOT/Serein.app/Contents/Info.plist")"
test "$INSTALLED_VERSION" = "$REMOTE_VERSION"

LOCAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")"
echo "local Info.plist version: $LOCAL_VERSION"
echo "github release version:   $REMOTE_VERSION"

echo "OK: GitHub update pipeline verified (download + DMG + app swap)."
echo "Menu path in app: Serein → Check for Updates…"
echo "Config: [updates] auto_check / github_token in ~/Library/Application Support/Serein/config.toml"
