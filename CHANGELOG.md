# Changelog

All notable changes to SlatePDF are captured here. Versions follow semver.

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
- Writes back to `~/Library/Application Support/SlatePDF/config.toml` and refreshes menus live

### Theme
- Night mode toggle (`i`) via inversion
- Minimal flat chrome, compact titlebar

### Known limitations
- Ad-hoc signed; Gatekeeper will prompt on first open (right-click → Open, or strip quarantine with `xattr -dr com.apple.quarantine SlatePDF.app`)
- Personal-use license, no redistribution
