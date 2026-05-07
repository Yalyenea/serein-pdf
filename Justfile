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

# Run Serein in dev mode via SwiftPM.
run:
    swift run

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
