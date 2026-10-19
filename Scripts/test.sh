#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .tmp

swift test --build-system native --disable-sandbox --no-parallel --disable-swift-testing 2>&1 | tee .tmp/xctest.log
if ! grep -q "Test Suite 'All tests' passed" .tmp/xctest.log; then
    echo "error: XCTest did not report a complete passing run" >&2
    exit 1
fi

SEREIN_TEST_BIN="$(swift build --build-system native --show-bin-path)"
SEREIN_TEST_PLATFORM="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer"
swiftc -parse-as-library -F "$SEREIN_TEST_PLATFORM/Library/Frameworks" Tests/SwiftTestingHost.swift -o .tmp/SereinSwiftTestingHost
DYLD_FRAMEWORK_PATH="$SEREIN_TEST_PLATFORM/Library/Frameworks" \
DYLD_LIBRARY_PATH="$SEREIN_TEST_PLATFORM/usr/lib" \
    .tmp/SereinSwiftTestingHost "$SEREIN_TEST_BIN/SereinPackageTests.xctest/Contents/MacOS/SereinPackageTests" --no-parallel 2>&1 | tee .tmp/swift-testing.log
if ! grep -Eq 'Test run with [1-9][0-9]* tests.* passed after' .tmp/swift-testing.log; then
    echo "error: Swift Testing did not report a complete passing run" >&2
    exit 1
fi
