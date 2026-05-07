# Changelog

All notable changes to Serein are captured here. Versions follow semver.

## [Unreleased]

### Visual
- Refresh the app icon with a quieter Serein identity: warm paper PDF shape, rain-clear blue-gray atmosphere, and no bright annotation accent
- Replace the centered highlight-mode badge with a compact inline reader indicator

### Performance
- Make PDF tabs lightweight on open: sessions keep URL/title/reading state first, while `PDFDocument` loads only when a reader, sidebar, annotation, or search path needs it
- Add a small live `PDFDocument` LRU so clean background PDFs can be released while the current pane, split pane, and dirty documents stay resident
- Keep Show All Tabs as a lightweight text overview instead of rendering PDF thumbnails

## [0.2.0] - 2026-04-23

This release focuses on keyboard-driven reading, better highlight text
extraction, and smoother integration with the rest of macOS.

### Keyboard and navigation
- Expand shortcut coverage so every configured command can be rebound and executed consistently
- Add Vim-style reading motions: `j` / `k` page turns, `ctrl+d` / `ctrl+u` half-page scroll, `g` / `shift+g` jump to document start/end
- Make search next/previous configurable and keep `cmd+g` / `cmd+shift+g` as the defaults
- Restore standard macOS app and window shortcuts, including `cmd+h`, `cmd+option+h`, and `cmd+m`
- Add highlight redo support

### Reading and documents
- Apply configured sidebar widths cleanly to restored and newly opened sessions
- Handle external PDF open events more reliably when Serein is used from Finder or other apps

### Highlights and extraction
- Improve highlight snippet extraction for Chinese text and OCR-heavy PDFs
- Add OCR-assisted fallback extraction path for highlights that do not yield clean PDF text directly

## [0.1.0] - 2026-04-21

First personal-use release. Complete macOS PDF reader with tabs, annotations,
search, compare split, multi-window workspaces, and a Spotlight-style recent
files launcher.

### Reading
- Four display modes (single page / single page continuous / two-up / two-up continuous)
- Fit-width calibrated from PDFKit row width so slide and paper PDFs land without horizontal crop
- Single-page mode recenters short pages when zoomed out
- Viewport anchor preserved across zoom and fit actions
- All-pages overview (`cmd+shift+o`) with pinch-style zoom

### Documents and windows
- Left vertical tabs or titlebar tabs, switchable live
- Multi-window workspaces (`cmd+shift+n`) with per-window tab sets
- Compare split in the center (`cmd+ctrl+\`), `option+click` to send a tab across
- Per-PDF memory for scale, page, and sidebar widths
- Session recovery on relaunch

### Right sidebar
- Outline / Pages / Search / Annotations (`cmd+shift+l` cycles outline/pages)
- Swap left and right sidebars (`cmd+shift+x`)

### Search
- Find bar (`cmd+f`) with `This Document` / `All Open` scopes
- Results grouped per session in the right sidebar
- First `enter` submits, repeated `enter` / `cmd+g` / `cmd+shift+g` navigate matches

### Annotations
- Default light pink highlights; `a` applies or enters highlight mode, `d` deletes
- Group-aware delete for multi-line highlights
- Undo stack (50 steps)
- Per-highlight comments, editable from the right sidebar
- Export as Markdown / Plain / JSON; `cmd+shift+e` copies Markdown
- Manual save (`cmd+s`) and auto-save every 10 minutes (configurable, `never` supported)

### Recent files launcher
- `cmd+shift+space` opens a Spotlight-style palette
- Title and path filtering, `space` multi-selects, `enter` opens
- Always-visible footer hint

### Settings
- General page: default display mode, `fit_width_on_open`, auto-save policy
- Shortcuts page: capture, clear, restore default, conflict detection
- Writes back to `~/Library/Application Support/Serein/config.toml` and refreshes menus live

### Theme
- Night mode toggle (`i`) via inversion
- Minimal flat chrome, compact titlebar

### Known limitations
- Ad-hoc signed; Gatekeeper will prompt on first open (right-click → Open, or strip quarantine with `xattr -dr com.apple.quarantine Serein.app`)
- Personal-use license, no redistribution
