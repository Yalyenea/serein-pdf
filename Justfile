# Serein — task runner
# Usage: `just` (lists targets), `just <target>`
# Install just: brew install just

BUNDLE_ID := "local.yfff.Serein"
APP_NAME  := "Serein"
BUILD_DIR := "build"
APP_BUNDLE := BUILD_DIR + "/" + APP_NAME + ".app"
INSTALL_DIR := "/Applications"

LSREGISTER := "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

default:
    @just --list

# Run all Swift tests.
test:
    swift test --disable-sandbox

# Verify GitHub Releases download + DMG install path (needs gh auth or SEREIN_GITHUB_TOKEN).
verify-update:
    ./Scripts/verify-github-update.sh

# Run Serein in dev mode via SwiftPM.
run:
    swift run

# Preview the local static product website.
website:
    uv run python -m http.server 4173 --bind 127.0.0.1 --directory Website

# Check required website files and references.
website-check:
    test -f Website/index.html
    test -f Website/README.md
    test -f Website/assets/styles.css
    test -f Website/assets/main.js
    test -s Website/assets/app-icon.png
    test -s Website/assets/serein-reader.png
    rg -q 'assets/styles.css' Website/index.html
    rg -q 'assets/main.js' Website/index.html
    rg -q 'assets/app-icon.png' Website/index.html
    rg -q 'assets/serein-reader.png' Website/index.html
    rg -q 'data-theme-toggle' Website/index.html
    rg -q 'data-lang-toggle' Website/index.html
    rg -q 'https://github.com/Yalyenea/serein-pdf/releases/latest' Website/index.html
    @echo "website check passed."

# Ensure the stable local signing identity exists in the login keychain.
signing-identity:
    ./Scripts/ensure-local-codesign-identity.sh

# Build a release .app bundle under build/Serein.app.
build:
    ./Scripts/make-app.sh {{BUILD_DIR}}

# Package the built .app into build/Serein-<version>.dmg.
dmg: build
    ./Scripts/make-dmg.sh {{BUILD_DIR}}

# Regenerate Resources/AppIcon.icns from Resources/AppIcon.png.
icon:
    ./Scripts/make-icon.sh

# Copy the built .app into /Applications (overwrites existing install).
install: build
    @echo "==> installing {{APP_BUNDLE}} -> {{INSTALL_DIR}}/{{APP_NAME}}.app"
    rm -rf "{{INSTALL_DIR}}/{{APP_NAME}}.app"
    cp -R "{{APP_BUNDLE}}" "{{INSTALL_DIR}}/"
    @echo "installed."

# Register the installed bundle with Launch Services so it appears in
# Finder's 'Open With' menu.
register:
    {{LSREGISTER}} -f "{{INSTALL_DIR}}/{{APP_NAME}}.app"
    @echo "registered {{BUNDLE_ID}} with Launch Services."

# Full release flow: build .app -> install -> register.
ship: install register
    @echo "done. Serein is installed."

# Remove build artifacts and the installed .app.
clean:
    rm -rf {{BUILD_DIR}} .build
    rm -rf "{{INSTALL_DIR}}/{{APP_NAME}}.app"

# Launch the installed Serein.app (not the dev build).
launch:
    open "{{INSTALL_DIR}}/{{APP_NAME}}.app"
