# Changelog

All notable changes to Serein are captured here. Versions follow semver.

## [Unreleased]

## [0.7.0] - 2026-09-19

### Website and licensing
- Publish the bilingual product website with features, release notes, documentation, and GitHub links.
- License Serein under GPL-3.0-only and include the license in release bundles.

### Reliability
- Keep comment dots above PDFKit page views after layout updates, align their click targets across macOS versions, and retain the final reading position after explicit zoom.
- Share annotations, saving, and undo between panes comparing the same PDF while keeping reading positions independent; release comparison sessions and stale undo records with their documents.
- Serialize persistence snapshots and writes to prevent older state from overwriting newer state. Preserve explicitly empty window lists.
- Download updates directly to disk, validate release size and checksum when supplied, and schedule installation only after document saving permits quitting. Restore the previous app if replacement fails.
- Preserve distinct multiline comments, use the accepted whole-word search match for previews, and leave document titles unchanged when file renaming fails.
- Release overview resources when leaving a PDF, reset library filters on refresh, and preserve input-method composition and Unicode caret positions in launchers.

### Reading
- Allow explicit zoom and page/text fitting while horizontal pan lock is enabled. Preserve the viewport anchor during scaling and lock the resulting horizontal position; magnification gestures remain blocked.
- Select text by clicking a starting point and Shift-clicking an endpoint, including across pages and from whitespace at line boundaries. Further Shift-clicks adjust the endpoint; switching documents clears the anchor. Preserve native dragging and double-click selection.
- Fix a crash during PDFKit's background form recognition by preserving its native document getter and clearing comment-icon caches explicitly when replacing documents.
- Save horizontal pan lock per PDF and restore it after closing or restarting, keeping other documents independent.
- Use the same page navigation as J/K for vertical trackpad turns in non-continuous Single Page and Two-Up modes. Preserve scrolling within zoomed pages and consume remaining motion after a turn so it cannot move the new page.

### Tabs
- Clicking a vertical sidebar tab or titlebar tab now switches the PDF even when the tab is not first in the strip. Close buttons on those tabs stay clickable.

### Chrome
- Hide the titlebar tab strip when the window has no tabs; restore it when a PDF or blank tab opens.
- Show a large, faint Baskerville italic `Serein` wordmark in empty windows and blank tabs, sized to the reader area and colored by the current theme.
- Draw the reader pane focus stroke only while split is on, so a single-pane window no longer has an inner frame.

### Palettes
- Command Palette is a compact two-column grid without search. Arrow keys move across commands, Enter or a click runs the highlight, and Esc or Cmd+K closes. Two-stage Cmd+K chords still work while the panel is open.
- Esc closes the recent-files launcher even when the reader is key. Duplicate titles show the parent folder.

### Appearance
- Keep PDF page spacing unchanged when toggling light and dark with `i`, preserving page position and zoom across all reading modes.
- Shortcut hints use compact SF Symbol chips in palettes, Settings, comment editors, and the presentation toolbar.
- Apply the selected theme to the filename toast, recent-files launcher, PDF library, open-tabs overview, command palette, shortcut keycaps, annotation editor, and presentation toolbar.
- Refresh open panels in place when switching themes, preserving search queries, selections, and unfinished annotation comments.

### Outline
- Restore text input in the floating outline filter; clicking the search field keeps the outline open while editing.

### Annotations
- Change the add-or-edit comment shortcut from `cmd+option+m` to `m`. Configs still on the old default migrate on launch.
- Enable File > Save when a reader window becomes key after new annotation edits, so Cmd+S writes without opening the File menu.
- Refresh comment icons immediately after adding, editing, or removing comments on highlights, underlines, and strikethroughs. Preserve annotation identity, stacking order, and one comment owner per multiline group.
- Keep one comment icon per multiline highlight by storing the shared comment on its first annotation. Consolidate identical comments in older Serein groups on open while preserving distinct notes and external annotations.
- Annotations list is a compact comment feed: snippet then comment, a quiet selection, a color bar, and no auto-selected first row. Snippets wrap to 4 lines and comments to 8; the full text stays in the tooltip.
- Clicking a comment icon or double-clicking a highlight opens Serein's comment panel. Handle annotation clicks and context menus without opening PDFKit's yellow note editor.
- Place comment markers in nearby whitespace (prefer the right of the line, then the page margin) so they do not cover following glyphs. Hide PDFKit's numbered badges and draw a small highlight-colored dot instead.
- Keep comment dots aligned with their click targets across page changes, scrolling, and zoom. Drawing, hit testing, and comment cards reuse page-space placements; annotation and page geometry changes invalidate them, and leaving pages releases cached layouts.
- Comment previews and editing share one 6pt-corner card. Click the icon or preview to edit in place, with a 150ms pointer transition between the annotation and card. Keep the icon visible and the card attached to the same corner as it grows.
- Measure wrapped comments with the native text control so multiline Chinese text is not clipped. Keep empty and short editors compact, with a right-aligned `Save ⌘↩` footer and no visible Esc hint.
- Refresh open comment panels and hover previews when the theme changes, including the highlight color strip and editor controls.

### Reading
- Add Fit Text Width (`cmd+option+0`) to the main reader: fit the current page or spread's text bounds with 12pt side margins and preserve vertical reading position. Apply once as manual zoom; leave textless pages unchanged. Configure `fit_text_width` in Settings → Shortcuts; `cmd+0` still fits page width.
- Keep formula references in their target preview column when body lines are staggered or contain short equations and superscripts; include equation numbers in the column bounds.
- Internal-link previews fit text width by default with 12pt side margins. Detect two-column text near the destination and zoom to its target column; single-column text, spanning headings, and uncertain layouts use the page's full text bounds. Pages without extractable text keep full-page width. Preserve the source PDF and restore user-adjusted zoom and position through preview history.
- Preserve the viewport and manual zoom when zoom commands or new highlights arrive before pending reading-position updates have been written back.
- Reference previews fill the available width in a 6pt-corner panel without a header. Follow internal links in the same preview, with Back/Forward arrows at the top left and Jump at the top right. Preview history restores scroll and zoom; following a new link after going back replaces the forward branch. Only Jump navigates the main reader, using the current preview target. Suppress comment popups in each copied page while preserving the source annotations.
- Clicking an internal PDF link opens a pane-local preview of the destination. Option-click, or Jump in the preview, still performs the centered navigation and records history.
- Add temporary pen (`P`), laser (`R`), and pointer (`V`) tools to demo mode (`Cmd+L`), with a bottom toolbar that can stay pinned or auto-hide. `Esc` returns to the pointer before exiting demo mode.
- Keep presentation ink attached to its page and separate in each window. `Cmd+Z` undoes the current page's last stroke, and `E` clears that page. Ink remains while turning pages, clears when leaving demo mode or switching documents, and is never written to the PDF.

### Performance
- All-pages overview (`Cmd+Shift+O`) rasterizes lazily instead of up front: only pages within one screen of the viewport render, off the main thread two at a time, and thumbnails are capped at 1200px on the long side. Offscreen pages release their bitmaps, a cost-bounded `NSCache` restores recently visited pages without re-rasterizing, zooming / resizing re-renders only visible cells, and leaving the overview frees every thumbnail immediately.
- Replace per-second PDF metadata polling with file and directory change events. Rebind monitoring after atomic replacements and directory recreation, and scan only the changed file for in-place writes.
- Detach Pages thumbnails while their sidebar is hidden or showing another mode. Cancelling queued overview renders releases their PDFs and completed bitmaps immediately.
- Remove pointer tracking while reading focus is disabled and reuse its drawing paths when geometry is unchanged.
- Skip rebuilding reading-history LRU order when saving progress for the current most-recent document.

### Maintenance
- Remove unused search and installer paths, obsolete views and callbacks, duplicate session state, and unused theme modes. Consolidate palette state updates and legacy session decoding.
- Share test fixtures and view queries, merge duplicate cases, and cover legacy session JSON decoding. Dispatch button actions directly in window tests to avoid premature test-runner exits caused by AppKit click animations.

## [0.6.2] - 2026-08-30

### Reliability
- Publish the v0.6.1 application changes in a verified DMG after removing redundant AppKit geometry assertions and running the test suite serially in CI.
- Preserve the selected text captured by the reader context menu when sending it to Codex.
- Use native macOS OpenSSL for local signing identities and ad-hoc signing for keychain-free release builds.

## [0.6.1] - 2026-08-30

### Annotations
- Hover comment cards only appear when a highlight has a comment; show after a short delay, wrap longer text up to a wider card, and suppress the card when the same item is already selected in the Annotations sidebar.
- Reader comment edit (`cmd+option+m` / context menu) uses a lightweight popover next to the highlight instead of forcing the right sidebar open.
- Annotations list is denser: no timestamps, tighter leading inset, section + snippet + comment only; column width is locked to the pane (no horizontal pan). Empty state shows a compact `A` / `⌘⌥M` hint; list supports double-click edit plus a context menu for Edit / Copy Snippet / Color / Delete (keyboard `D` / Delete also removes the selected row).
- Activating an annotation jumps with a short color pulse instead of leaving a dashed PDF selection.
- Double-clicking a highlight opens the Annotations sidebar and reveals the matching row; `1` / `2` / `3` switch pink / yellow / green while highlight mode is active.
- Add `File > Export All Open Highlights…` for a document-then-page Markdown / Plain Text summary or aggregate JSON across the current window.
- Remove Vision OCR from highlight snippet extraction; PDFs without a text layer use the existing `Untitled Highlight` label.
- Keep PDFKit's native contextual actions, including system translation and lookup services, alongside Serein's highlight and comment actions.

### Outline
- Floating outline rail appears whenever the Outline *pane* is not showing — right sidebar closed, or open on Pages / Search / Annotations — not only when the whole right sidebar is collapsed.
- Add a compact heading filter that keeps matching nodes and their ancestor paths without changing the saved collapse state.

### Docs
- Slim live docs for next-step work: `TASKS.md` and `REVIEW.md` keep only open items; completed milestone checklists and the full 2026-06 review snapshot move to `docs/archive/`; `PROJECT.md` pending-milestone section now covers M12 empty-state, M13.1 site follow-up, multi-theme presets, and engineering debt pointers.

### Navigation
- Stabilize real Back/Forward input and playback: `Cmd+[` / `Cmd+]` no longer depends on stale menu enablement, Pages keeps its origin until PDFKit finishes navigating, and split comparison panes replay canonical document history without consuming failed entries.
- Make `Cmd+[` / `Cmd+]` history pane-local and session-aware: exact page points survive repeated back/forward, same-page jumps, cross-document Outline/Search navigation, and tab switches; ordinary scrolling and sequential turns do not flood history.
- Treat Outline destinations, Pages thumbnails, PDF internal links, Search results, and annotations as explicit navigation intents; route internal GoTo links through the centered reader path from the first click, preserve precise destination points, and avoid duplicate single/double-click jumps.
- Persist ordinary wheel/trackpad viewport changes, restore exact anchors after display-mode reflow, and keep new/clamped pages on their real PDF top instead of the PDF-coordinate origin.
- Fix document edges and reading boundaries: `G` reaches the real document bottom, non-continuous half-page commands finish the current PDF before crossing a continuous-reading group, backward transitions land at the previous bottom, and odd/even Two-Up spreads stop correctly.
- Keep fit-width active and recompute scale when a page turn changes page shape.

### Reading
- Let trackpad pinch, smart zoom, and PDFKit `zoomIn`/`zoomOut` leave fit-width or fit-height instead of snapping back; keep layout/page-turn refits.
- Horizontal pan lock now also blocks pinch, smart zoom, Option/Command+scroll zoom, and `cmd+=` / `cmd+-`, so scale cannot drift the locked X.
- Copy the current page as an image (`cmd+option+c`, File menu, or reader context menu). Rasterizes the focused pane's current page at 2× mediaBox with annotations, without the night-mode display filter.

### Find
- After choosing a result with the Find bar arrow keys, `Enter` activates that exact selection before repeated-submit navigation resumes.
- Add match-case (`Aa`) and whole-word (`Word`) options for both current-document and All Open search.

### Chrome / Layout
- Empty windows now auto-collapse the outline pane (M12-010): with nothing open, the reader owns the window, and the tabs pane stays as the quick-entry home for recent files. Opening the first document restores the outline pane automatically, unless you explicitly toggled it while the window was empty.
- The right sidebar shows weakened chrome when no PDF is open (M12-011): the Outline / Pages / Search / Annotations segmented control and panes hide behind one centered "No Document Open" state, so a blank tab never looks like a ready-but-empty panel.
- The left sidebar gains a permanent `Documents` section title; in an empty window the Recent PDFs list moves up under the header as the primary quick-reopen content, falling back to a shared hint when recents are disabled or absent (M12-012).
- Add a shared `EmptyStateView` (12 pt semibold / 11 pt secondary, centered) and rebuild `PlaceholderViewController` on it, so sidebar empty states and placeholder panes share one typography and color language (M12-013).
- Empty-state placement calibration (M12-014): the right sidebar's no-document copy centers vertically instead of leaving a titlebar-anchored dead zone; the left sidebar's `Documents` header gives the top inset purpose.
- Empty windows and blank tabs keep a pure blank center reader (no onboarding / shortcut cheatsheet); loading errors still surface there. Side panes stay blank without instructional empty copy.
- Hide left/right sidebar split dividers while retaining AppKit's normal one-point layout geometry and expanded drag targets.
- Remove residual “seam” between panes: sidebars paint a solid `readerBackdrop` surface (no sidebar vibrancy), normal light/dark chrome unifies split/pane with the reader, the titlebar separator is disabled, and the obsolete opacity control is removed while its config key remains readable.
- Keep preferred sidebar widths across collapse/expand: only persist divider drags (user mouse), re-pin after AppKit settles, and raise sidebar holding priority so headless CI layout no longer clobbers 220/320 defaults.

### Reliability
- Keep same-PDF comparison sessions out of URL-level reading-state persistence, and persist true reading-state LRU order across launches without losing the legacy dictionary format.
- Replace navigation false-green tests with real PDFView page, selection, viewport, cross-session, four-mode, odd/even spread, and top/bottom boundary assertions.
- Stabilize sidebar toggle layout tests for CI: pin default window size, wait for settled widths, assert store preferred widths survive programmatic toggles.
- Make search results an explicit window-level `SearchSnapshot`, so reads no longer perform hidden PDF work and clearing one window cannot invalidate another window's query.
- Move theme selection into the `@MainActor` `ThemeManager`; dynamic colors now capture immutable `ThemeSnapshot` values from `ThemeRegistry`.
- Extract reader annotation hit-testing, hover preview, menus, comment popovers, and focus pulse into `ReaderAnnotationInteractionController`.

## [0.6.0] - 2026-08-01

### Chrome / Layout
- Stabilize left/right sidebar on/off: store visibility is the single source of truth; one chrome pass collapses/expands, pins preferred widths so the center reader always gets the remainder (no overlay), ignores reverse split sync during programmatic apply, and reflows fit-width/fit-height PDF to the new center size.
- Add a Notion-style floating outline when the semantic Outline pane is hidden: compact heading marks sit on the reader edge, hover opens the existing full outline as an overlay, either vertical edge resizes symmetrically around the center and remembers height per window, General / `layout.floating_outline_height` sets the global default, clicks keep established navigation, and empty outlines stay hidden.

### Settings
- Keep General, Library, and Shortcuts at one compact 680 pt width so page switching never shifts the window horizontally; group General by responsibility and compress shortcut rows into aligned title/default and capture/action areas without horizontal scrolling.

### Find
- Fix find-next navigation: `cmd+g` / repeated Enter now advance matches. Search list keeps a stable selection key across store reloads, same-session activate is skipped, and find shortcuts still fire while the find-bar field editor is focused.

### Reliability
- Test hygiene: stop several UI suites from writing real UserDefaults; kill false-green hot-reload / title / library / vim-grid / autosave assertions; share in-memory store doubles.
- Further test isolation: DocumentStoreTests always injects in-memory recent/persistence; WindowChrome closes every main window and uses isolated stores; NightModeStyleTests restores global theme after each case.
- Shared test Support: PDF fixtures, view query, key events, temp config roots; migrate Annotations/VerticalTabs/SearchNav/Highlight/DocumentStore/WindowChrome; collapse AppConfiguration default laundry-lists; search perf asserts correctness not wall-clock.

### Reading
- Center the PDF horizontally when zoomed out so the page is narrower than the viewport (continuous and two-up modes, not only Single Page).
- Fix zoom-out visual centering: AppKit was pinning clip origin to the document frame min, canceling margin offsets; keep clip origin at zero when content fits.
- Simplify zoom path: pin manual scale mode before store writeback and drop the triple post-store viewport restore loop.
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
