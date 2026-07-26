# Serein

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Serein icon"/>
</p>

Native macOS PDF reader — Swift + AppKit + PDFKit. Minimal, flat, compact.

Local website preview lives in [Website](Website/). It is a static product
site for showcase, download notes, and compact docs.

## Features

- Tabbed documents with switchable layouts: left vertical sidebar or adaptive titlebar tabs
- `cmd+o` supports selecting PDF files and folders; selected folders are scanned for PDFs automatically
- `cmd+t` creates an untitled blank tab for a clean reading workspace; blank tabs are not PDF-backed, recent history entries, or relaunch-restored sessions
- Right pane hosts **Outline + Pages + Search + Annotations**; Outline wraps long titles with tight line spacing, no horizontal panning, and one-click tree expand/collapse, while all search / annotation previews stay on the right
- Right sidebar modes keep a consistent pane footprint, so switching Outline / Pages / Search / Annotations does not visually widen or narrow the sidebar
- Find bar supports `This Document` / `All Open`; opening it with selected PDF text searches that text immediately, `All Open` scopes to PDFs open in the current window, typing alone does not search, first `enter` submits, repeated `enter` / `cmd+g` / `cmd+shift+g` continue match navigation
- Reader navigation keeps the compact Vim-style layer: `c` toggles single-page continuous mode, `j` / `k` page turns, `ctrl+d` / `ctrl+u` half-page scroll, `g` / `shift+g` jump to the document edges
- Compare split in the center reader (`cmd+ctrl+\`) opens a compact candidate chooser and can arrange the two independent readers left/right or top/bottom from the View menu
- Split follows browser-style tab pairs: a normal click restores the bound pair or leaves it hidden, while `option+click` / `option+enter` edits the focused pane or creates a current + target pair from single-pane mode
- New windows always start empty and in single-pane mode; relaunch restore also starts single-pane, split stays an explicit in-session toggle
- Multi-window workspaces (`cmd+shift+n`) with per-window tab sets, sidebar, search, and recently-closed state
- Opening a PDF that is already open focuses the existing tab and window instead of creating a duplicate tab
- Window commands can merge every Serein window, move the current PDF into a new or existing window, and vertical/titlebar tabs can be dragged directly between windows
- Main windows participate in native macOS green-button window management: Full Screen, Move & Resize, Fill, Center, and Fill & Arrange on supported macOS versions
- Show All Tabs (`ctrl+tab`) opens a lightweight text overview for every tab in the current window; `option+enter` / `option+click` uses the same split-edit behavior as the tab strip
- Continuous reading groups from the tab context menu let selected PDFs read as one ordered flow; page turns cross PDF boundaries and the right Outline groups every PDF together
- `cmd+w` closes all selected tabs when multiple PDF tabs are selected; otherwise it closes the current tab/window as usual
- `cmd+shift+w` closes the current window while preserving the normal close confirmation for unsaved annotations
- Opening many PDFs stays lazy: tabs are created from URL/title first, while PDFKit documents, outlines, annotation caches, and search caches load only when a reader or sidebar actually needs them
- Clean PDFs hot-reload when LaTeX, Typst, or another external compiler rewrites the open file in place or replaces it atomically, preserving the live page; PDFs with unsaved Serein annotations are left untouched
- On first launch, Serein asks for persistent access to `/Users` so PDFs under user folders stay readable after reinstalling
- PDF Library folders can be configured in Settings; `cmd+k`, then `cmd+o` opens a two-pane library browser with an All tab, per-library tabs, folder scopes, indexed search, and direct PDF opening
- Spotlight-style recent-files launcher (`cmd+shift+space`) stays compact, hides traffic lights, supports title/path filtering, `space` multi-select, `enter` open, and an always-visible footer hint
- Recent history keeps up to 200 entries and automatically prunes missing file links every 24 hours
- Opened PDFs are also noted to macOS native recent documents, and the active PDF URL is exposed to the window for system window/document integration
- Optional recent PDFs footer in the left sidebar (toggle in Settings) for one-click reopen
- Blank space in the document sidebar drags the current window while tabs, close buttons, scrolling, and the divider keep their own interactions
- Swap left and right sidebars on the fly (`cmd+shift+x`) or via Settings
- Settings General can edit the default left and right sidebar widths and native material sidebar opacity
- Theme controls now split into `Mode`, `Light Theme`, and `Dark Theme`
- Light themes support `Normal` / `Rose Pine Dawn`; dark themes support `Normal` / `Rose Pine Moon`
- `i` toggles the current appearance mode between light and dark while keeping your selected light / dark themes
- `cmd+k`, then `cmd+t` switches the current light or dark theme, VS Code-style
- `cmd+k` chords also refresh the PDF Library index, jump to Library / Shortcuts settings, share the current PDF, merge windows, and move the current PDF to a new window
- Rose Pine Dawn replaces only the PDF's white paper with an Obsidian-like warm surface, preserving the document's original text and accent colors
- Rose Pine Moon maps the PDF's white/black endpoints to a dark paper/text pair, preserves warm/cool accent direction, and keeps the surrounding sidebars one shade deeper
- Pink-first highlight workflow (`a` to highlight) with a compact inline reader indicator
- Pink / yellow / green highlights use theme-specific sRGB palettes for Normal, Rose Pine Dawn, and Rose Pine Moon
- `File > Share…` can share the original PDF, a clean copy, or highlights as Markdown text; `File > Export Clean Copy…` writes a PDF with user-visible annotations removed while preserving links and form widgets
- Highlights can carry comments in the right sidebar, and Markdown export is page-grouped as snippet + comment for note-taking
- Settings now includes a Shortcuts page with capture, clear, restore-default, and conflict rejection
- Settings resizes to fit the current page, so Shortcuts gets a larger window without making General oversized
- Find bar (`cmd+f` for current document, `cmd+shift+f` for all open PDFs) preloads selected PDF text when available; Esc clears search and exits
- All-pages overview (`cmd+shift+o`) seamless viewport-fit grid (no nested panel); zoom for manual size; click a page to jump
- Auto-update from GitHub Releases (check on launch + **Serein → Check for Updates…**); private repos need `[updates] github_token` in config.toml
- Single Page mode keeps fully visible pages centered on both axes and clamps blank-area scrolling, while zoomed-in pages can still pan normally
- Demo mode (`cmd+l`) for presentation-style reading: enters full screen, fits the whole page with stable single-page framing, hides reader chrome, and restores the prior layout on `cmd+l` or Esc
- Immersive mode (`cmd+ctrl+l`) opens both sidebars only when none are visible; otherwise it hides both sidebars and tab chrome while keeping the current window size
- Per-PDF memory: scale and page persist across launches; sidebar widths are window-level runtime state seeded from layout defaults
- Switching PDFs briefly shows the current file name at the top of the reader, so fast tab changes stay oriented without adding permanent chrome
- Config-driven defaults via `~/Library/Application Support/Serein/config.toml`

## Requirements

- macOS 14+
- Swift 6.1 (Xcode 15.3+ toolchain)
- `just` task runner (`brew install just`)
- `duti` for setting the default PDF handler (`brew install duti`)

## Dev loop

```sh
just            # list targets
just test       # run Swift tests
just run        # run dev build via SwiftPM
just website    # preview the local static website
just website-check
```

## Ship to your Mac

```sh
just signing-identity # creates/reuses the local Serein signing identity
just build      # produces build/Serein.app (signed with the local identity)
just install    # copies the .app to /Applications
just register   # lsregister -f so Finder's Open With sees it
just dmg        # packages build/Serein-<version>.dmg
just launch     # open /Applications/Serein.app
```

`just build` signs with `Serein Local Code Signing` by default, creating that
self-signed code-signing identity in the login keychain on first use. Keeping a
stable signing identity prevents local reinstalls from changing the app identity
to a new cdhash-only ad-hoc signature. Set `SEREIN_CODESIGN_IDENTITY` to use a
different local or Developer ID identity.

Full release pipeline:

```sh
just test
just dmg
just ship       # build → install → register
```

## Configuration

Runtime config lives at `~/Library/Application Support/Serein/config.toml`
and is created on first launch. Edit, then restart Serein.

```toml
[appearance]
mode = "system"               # or "light" / "dark"
light_theme = "normal"        # or "rose_pine_dawn"
dark_theme = "rose_pine_moon" # or "normal"

[reader]
default_display_mode = "single_page_continuous"
fit_width_on_open = false

[annotations]
auto_save = "after_10_minutes"   # or "never"

[layout]
left_sidebar_width = 220
left_sidebar_min_width = 36
left_sidebar_max_width = 520
right_sidebar_width = 320
right_sidebar_min_width = 120
right_sidebar_max_width = 720
sidebars_swapped = false
show_recent_files_in_sidebar = true
sidebar_opacity = 0.48

[library]
folders = ["/Users/your-name/Documents/Papers"]

[access]
roots = ["/Users"]
root_bookmarks = [] # managed by Serein; do not edit manually

[shortcuts]
switch_current_theme = "none"   # cmd+k, cmd+t is a built-in chord
open_library_pdf = "none"       # cmd+k, cmd+o is a built-in chord
refresh_library_index = "none"  # cmd+k, cmd+r is a built-in chord
open_library_settings = "none"  # cmd+k, cmd+l is a built-in chord
open_shortcut_settings = "none" # cmd+k, cmd+s is a built-in chord
share_document = "none"         # cmd+k, cmd+e is a built-in chord
export_clean_copy = "none"
new_blank_tab = "command+t"
copy_current_pdf_path = "command+shift+c"
toggle_continuous_reading = "none"
merge_all_windows = "none"      # cmd+k, cmd+m is a built-in chord
move_current_pdf_to_new_window = "none" # cmd+k, cmd+n is a built-in chord
# ...
```

- Layout widths seed new and restored windows. Dragging a sidebar changes the
  current window runtime width, switching PDFs does not resize panes, and
  restart goes back to the config defaults.
- `mode = "system"` follows the current macOS appearance.
- `light_theme` and `dark_theme` are selected independently, so you can pair
  `Normal` light with `Rose Pine Moon`, or `Rose Pine Dawn` with `Normal`
  dark, without changing the mode model.
- `sidebars_swapped = true` flips the left and right panes — window-level widths
  travel with the panes so your narrow tabs pane stays narrow after the swap.
- `fit_width_on_open` switches fit-to-width on/off for **all currently open
  documents** as soon as you toggle it — any document you've manually zoomed
  stays pinned at your scale.
- `library.folders` can contain one or more folders. The library browser scans
  them recursively, groups results by library root and PDF folder, keeps a
  lightweight in-session catalog cache, and invalidates it when the configured
  folders change.
- `access.roots` defaults to `/Users`. `access.root_bookmarks` stores the
  persistent macOS access token created on first launch, so reinstalling Serein
  does not require re-authorizing each PDF under user folders.
- Setting a shortcut to `none` clears it completely; Serein will not silently
  fall back to the default binding after restart.

## Keyboard shortcuts

Defined in `[shortcuts]` above. Highlights:

| Action | Shortcut |
|---|---|
| Highlight selection / enter highlight mode | `a` |
| Exit highlight mode | `esc` |
| Toggle light / dark mode | `i` |
| Switch current theme | `cmd+k`, then `cmd+t` |
| Refresh PDF Library index | `cmd+k`, then `cmd+r` |
| Open Library settings | `cmd+k`, then `cmd+l` |
| Open Shortcuts settings | `cmd+k`, then `cmd+s` |
| Save annotations | `cmd+s` |
| Share current PDF | `cmd+k`, then `cmd+e` |
| Export clean copy | configurable, default none |
| Copy highlights as Markdown | `cmd+shift+e` |
| Copy current PDF path | `cmd+shift+c` |
| Open PDFs / folders (scan PDFs) | `cmd+o` |
| Open from PDF Library | `cmd+k`, then `cmd+o` |
| New blank tab | `cmd+t` |
| Fit width / height | `cmd+0` / `cmd+9` |
| Toggle Single Page Continuous | `c` |
| Select document tabs 1–3 | physical left `cmd+1` / `cmd+2` / `cmd+3` |
| Single Page Continuous | physical right `cmd+2` |
| Other display modes | physical right `cmd+1` / `cmd+3` / `cmd+4` |
| Zoom in / out | `cmd+=` / `cmd+-` |
| Find current / all open PDFs | `cmd+f` / `cmd+shift+f` |
| Find next / previous match | `cmd+g` / `cmd+shift+g` |
| Show current PDF in Finder | `cmd+r` |
| Half-page down / up | `ctrl+d` / `ctrl+u` |
| Jump to first / last page | `g` / `shift+g` |
| Close selected tabs, or current tab/window | `cmd+w` |
| Close current window | `cmd+shift+w` |
| Reopen closed tab | `cmd+shift+t` |
| Show all tabs | `ctrl+tab` |
| Toggle continuous reading for selected tabs | Tab context menu |
| New window | `cmd+shift+n` |
| Merge all windows | `cmd+k`, then `cmd+m` |
| Move current PDF to new window | `cmd+k`, then `cmd+n` |
| Move current PDF to an existing window | Window menu, or drag its tab into that window |
| Quick recent-files launcher | `cmd+shift+space` |
| Toggle sidebar tabs / titlebar tabs | `cmd+shift+1` / `cmd+shift+2` |
| Toggle left / right sidebar | `cmd+b` / `cmd+option+b` |
| Toggle demo mode | `cmd+l` |
| Toggle immersive mode | `cmd+ctrl+l` |
| Toggle compare split | `cmd+ctrl+\` |
| Choose left/right or top/bottom split | View menu |
| Toggle right sidebar: Outline / Pages | `cmd+shift+l` |
| Swap left and right sidebars | `cmd+shift+x` |
| All-pages overview | `cmd+shift+o` |
| Undo last highlight edit | `cmd+z` |

Standard macOS app/window shortcuts are available too, including `cmd+h`,
`cmd+option+h`, `cmd+m`, and native macOS green-button tiling shortcuts.

## Docs (source of truth)

| File | Role |
|---|---|
| [PROJECT.md](PROJECT.md) | Product scope, architecture, milestones |
| [TASKS.md](TASKS.md) | Execution checklist (including REVIEW 5.1–5.4) |
| [REVIEW.md](REVIEW.md) | Engineering review: highlights, debt, roadmap (`✅` / `[ ]`) |
| [CHANGELOG.md](CHANGELOG.md) | User-facing and engineering change log |

## Repo layout

```
App/         AppKit entry point, window + split + settings
Core/        Document session store, config, persistence
Features/    Annotation service, exporter, highlight colors, shortcut controller
UI/          CenterReader, LeftTabs, RightOutline, TitlebarTabs
Tests/       Swift Testing + XCTest suites
Resources/   Info.plist, AppIcon.png/.icns
Scripts/     make-app.sh, make-icon.sh
Website/     Local static product website
Justfile     Task runner entrypoints
```

## License

Personal use. No redistribution.
