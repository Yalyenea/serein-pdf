# Changelog

All notable changes to Serein are captured here. Versions follow semver.

## [Unreleased]

### Reading
- Add horizontal pan lock: press `l` to center the page on X and block left/right panning while zoomed; vertical scroll, page turns, selection, and highlights stay free. Toggle again to unlock. Focused pane only; light `H-lock · L` badge when active.
- Pan lock forbids horizontal input at the source: a local `scrollWheel` monitor drops pure left/right gestures and zeros diagonal X before PDFKit sees them; the custom clip view still pins X as a final belt.

## [0.5.0] - 2026-07-27

### Reading Focus
- Add a cursor-following reading focus mode: press `f` to dim everything outside a compact rounded reading band without intercepting PDF selection, links, dragging, or scrolling.
- Add `option+f` window-level controls for Page, Column (half-page), or Custom width plus adjustable height; Settings General configures the defaults.
- Keep split readers synchronized, follow the actual PDF page geometry, and strengthen the surrounding shade in dark mode with a subtle edge shadow and no stitched gradients.

### Reliability
- Backfill missing `new_blank_tab` in config self-heal keys and add a defaultContents/render/requiredKeys consistency test.
- Strip TOML inline `#` comments outside quoted strings when parsing config values.
- Log document-store and reading-state persistence failures via `os.Logger` instead of swallowing them with `try?`.
- Prefer the topmost overlapping highlight under the cursor when several annotations stack.
- Add a PDFKit private-view sentinel test so night-mode chrome breaks loudly on macOS renames.

### Performance
- Cap reading-state history at 500 entries with LRU eviction and debounced UserDefaults writes; flush on quit.
- Skip full workspace JSON rewrite on pure reading-position / zoom writeback.
- Add `.readingPosition` store-change mask so page turns no longer rebuild tab strips, search result lists, or annotations lists.
- Diff-guard vertical and titlebar tab rebuilds with a session fingerprint.
- Cache the shortcut handler map for the app lifetime.

### UX
- GitHub Releases auto-update: launch check + **Serein → Check for Updates…** downloads the latest `Serein-*.dmg`, replaces the installed app, and relaunches (private repo needs `[updates] github_token`).
- Move the current PDF to any existing Serein window from the Window menu, or drag a vertical/titlebar tab directly between windows without losing its reading state.
- Let compare split switch between left/right and top/bottom layouts while keeping the same pane sessions and focus.
- Preserve the PDFView's live page across external-file hot reloads, even when the store has not yet received the latest page-change event.
- Drag the reader window from blank space in the document sidebar without stealing tab, close, divider, or scroll interactions.
- Use physical left `cmd+1/2/3` to select the first three document tabs; physical right `cmd+1/2/3/4` retains the four configured reader display modes.
- All-pages overview (`cmd+shift+o`) uses a seamless custom grid (no nested panel/chrome): viewport-fit tiling, same surface color as the reader, click page to jump and exit.
- Empty reader state now shows a single onboarding panel with `⌘O`, recent-files shortcut, and drag-and-drop PDF open hints.

### Docs
- Add REVIEW.md: full-code project review covering product highlights, implementation highlights, ranked weaknesses, and an improvement roadmap.
- Sync REVIEW / TASKS / PROJECT status for the near-term engineering pass: completed 5.1 items marked done, open 5.2–5.4 items kept as checklists.
- Mark M8–M10 (including M10.5–M10.13 hand-test waves) fully complete across TASKS / REVIEW / PROJECT.

### Website
- Rebuild the product site in an editorial / archive layout (warm paper, serif display, hairline brand mark, grain, rise/reveal, light·dark, EN/中文), modeled after Jump-style knowledge-tool landings while keeping Serein-specific copy and assets.
- Track follow-up website polish in `TASKS.md` M13.1 (real feature screenshots, deploy, copy pass).
- Add a local static Serein product website with showcase, download notes, compact docs, and a real app screenshot captured from a synthetic PDF.

### Packaging
- Sign local app builds with a stable `Serein Local Code Signing` identity instead of ad-hoc cdhash-only signatures, so reinstalling the app keeps a consistent macOS identity for persisted file access.

### Reading
- Make compare split behave like a browser split pair: normal tab activation restores or hides the pair, while Option activation edits the focused pane
- Add a compact secondary-pane candidate chooser for compare split, including a same-PDF comparison session with independent reading state and no regular tab/history/persistence footprint
- Fit both panes to width automatically when compare split opens, including PDFs that were previously pinned at a manual zoom level
- Add plain `c` as a reader toggle between Single Page and Single Page Continuous while keeping `cmd+2` as the direct Single Page Continuous command
- Keep fully visible Single Page slides centered on both axes and clamp blank-area scrolling, while preserving panning for zoomed-in pages
- Let Esc exit `cmd+l` Demo mode and restore the prior reader chrome.
- Focus the Go to Page input immediately and keep Return from being intercepted by tab rename handlers
- Preload selected PDF text into Find and search it immediately for both current-document and all-open searches.

### Tabs
- Add `cmd+t` to create an untitled blank tab; blank tabs are not PDF-backed, do not enter recent/reopen history, and are not restored after relaunch
- Add `cmd+shift+c` to copy the current PDF path, and leave continuous reading on the tab context menu by default
- Make titlebar tabs draw as a low-radius, adaptive-width strip whose selected tab is flush with the base bar.

### Right Sidebar
- Let Outline titles wrap with larger text, tighter internal line spacing, compact dynamic row heights, and no visible scrollbars or horizontal sliding
- Keep Outline rows pinned to the current sidebar width when the pane narrows, and add one-click expand/collapse for the outline tree
- Keep collapsed Outline rows top-anchored, clear stale rows when switching PDFs, and lay out Outline rows with direct frames instead of stack-view constraints to reduce expand/collapse lag.

### Performance
- Make left/right sidebar toggles use lightweight store notifications and zero-duration split-view collapse, so pure chrome changes no longer rebuild reader, tabs, outline, search, or annotations state.

### Visual
- Use theme-specific sRGB palettes for pink, yellow, and green highlights across Normal, Rose Pine Dawn, and Rose Pine Moon.
- Match Rose Pine Dawn more closely to Obsidian: replace the PDF's white paper with the warm Dawn surface while leaving document colors intact, and use flat opaque theme chrome.
- Give Rose Pine Moon the same paper-first treatment: map white and black to the Moon surface/text endpoints, preserve warm/cool accent direction, and separate the dark paper from the deeper sidebar base.

### Recent Files
- Route Return and keypad Enter at the recent-files panel level so the highlighted or selected recent PDFs open reliably
- Note successfully opened PDFs to macOS native recent documents.
- Focus the existing tab/window when an already-open PDF is opened again via system open, Open Recent, PDF Library, or `cmd+o`.

### Sharing
- Add `File > Share…` with Original PDF, Clean PDF Copy, and Highlights Markdown payloads, plus a `cmd+k`, then `cmd+e` chord.
- Add `File > Export Clean Copy…` and a PDFKit clean-copy path that removes visible/user annotations while preserving links and form widgets.
- Make Markdown highlights export page-grouped and note-friendly, keeping snippets and comments without color metadata.

### Settings and Windows
- Make sidebar widths window-level runtime state seeded from layout defaults, so switching PDFs no longer resizes sidebars.
- Let Settings General edit default left and right sidebar widths plus native material sidebar opacity.
- Keep the Settings General / Library / Shortcuts page tabs at equal widths for a steadier header.
- Change `cmd+ctrl+l` so it opens both sidebars only when both are closed; any visible sidebar state closes both sidebars.
- Keep main window represented URL and filename synchronized with the active PDF for native macOS window/document integration.

## [0.4.0] - 2026-05-19

### Windows
- Support native macOS green-button window management for main reader windows, including full screen, Move & Resize, Fill, Center, and Fill & Arrange on supported macOS versions
- Keep transparent-titlebar window dragging from reaching the PDF reader, so moving the window no longer scrolls the open PDF
- Add `cmd+shift+w` to close the current window without changing `cmd+w` tab-closing behavior

### Reading
- Hot-reload clean PDFs when LaTeX, Typst, or another external tool rewrites the open file in place or replaces it atomically, while leaving dirty annotation sessions untouched
- Briefly show the current PDF file name at the top of the reader after switching documents
- Request and persist `/Users` access with a security-scoped bookmark on first launch so reinstalling the app does not repeatedly prompt for PDFs under user folders

### Tabs
- Let `cmd+w` close all selected PDF tabs when multiple tabs are selected, while preserving the normal current-tab/window close behavior otherwise

## [0.3.0] - 2026-05-10

### Visual
- Refresh the app icon with a quieter Serein identity: warm paper PDF shape, rain-clear blue-gray atmosphere, and no bright annotation accent
- Replace the centered highlight-mode badge with a compact inline reader indicator

### Performance
- Update highlight annotation caches incrementally after local edits so applying a highlight no longer rebuilds every highlight snippet in the PDF
- Make PDF tabs lightweight on open: sessions keep URL/title/reading state first, while `PDFDocument` loads only when a reader, sidebar, annotation, or search path needs it
- Add a small live `PDFDocument` LRU so clean background PDFs can be released while the current pane, split pane, and dirty documents stay resident
- Keep Show All Tabs as a lightweight text overview instead of rendering PDF thumbnails
- Cache the PDF Library catalog per configured folder set and precompute lightweight root, folder, and search indexes so reopening the library does not rescan unchanged folders
- Disable AppKit state restoration for Serein windows so menu-triggered UI changes do not recursively persist the PDFKit view tree
- Hide the PDFKit document subtree from accessibility inspection to keep menu testing and automation responsive on text-heavy PDFs
- Keep menu validation lightweight by checking for highlight annotations without building OCR-backed export snippets
- Disable automatic AppKit item validation on Serein-managed menus and refresh their enabled/checkmark state through a lightweight menu delegate

### Windows
- Add commands to merge all Serein windows into the current window and move the current PDF into a new window

### Reading
- Add continuous reading groups for multiple selected PDFs: `cmd+shift+c` or the tab context menu enables ordered cross-PDF page turns, tab group indentation, and a combined right-sidebar Outline grouped by PDF
- Add configurable PDF Library folders with a two-pane library browser for root tabs, folder scopes, search, and opening library PDFs

### Keyboard
- Restore the VS Code-style `cmd+k`, then `cmd+t` theme chord for switching the current light or dark theme
- Add `cmd+k`, then `cmd+o` for opening the PDF Library browser without falling through to the standard Open panel
- Add `cmd+k` chords for refreshing the PDF Library index, jumping to Library / Shortcuts settings, merging windows, and moving the current PDF to a new window; chord-only commands are also visible in the macOS menu bar

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
