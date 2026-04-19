# SlatePDF — task runner
# Usage: `just` (lists targets), `just <target>`
# Install just: brew install just

BUNDLE_ID := "local.yfff.SlatePDF"
APP_NAME  := "SlatePDF"
BUILD_DIR := "build"
APP_BUNDLE := BUILD_DIR + "/" + APP_NAME + ".app"
INSTALL_DIR := "/Applications"

LSREGISTER := "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

default:
    @just --list

# Run all Swift tests.
test:
    swift test

# Run SlatePDF in dev mode via SwiftPM.
run:
    swift run

# Build a release .app bundle under build/SlatePDF.app.
build:
    ./Scripts/make-app.sh {{BUILD_DIR}}

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

# Set SlatePDF as the system default handler for PDFs.
# Requires `duti` (brew install duti). If absent, fall back to opening
# a sample PDF via SlatePDF, which prompts macOS to remember it.
set-default:
    @if command -v duti >/dev/null 2>&1; then \
        duti -s {{BUNDLE_ID}} com.adobe.pdf all && \
        echo "default PDF handler set to {{BUNDLE_ID}}"; \
    else \
        echo "duti not found. Install: brew install duti"; \
        echo "or set default manually: Finder -> Get Info on a PDF -> Open With -> SlatePDF -> Change All..."; \
        exit 1; \
    fi

# Full release flow: test -> build .app -> install -> register -> set-default.
ship: test install register set-default
    @echo "done. SlatePDF is installed and set as your default PDF viewer."

# Remove build artifacts and the installed .app.
clean:
    rm -rf {{BUILD_DIR}} .build
    rm -rf "{{INSTALL_DIR}}/{{APP_NAME}}.app"

# Launch the installed SlatePDF.app (not the dev build).
launch:
    open "{{INSTALL_DIR}}/{{APP_NAME}}.app"
