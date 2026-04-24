# SlatePDF

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="SlatePDF icon"/>
</p>

Native macOS PDF reader — Swift + AppKit + PDFKit. Minimal, flat, compact.

## Features

- Tabbed documents with switchable layouts: left vertical sidebar or titlebar tabs
- Right pane hosts **Outline + Pages + Search + Annotations**, and all search / annotation previews stay on the right
- Right sidebar modes keep a consistent pane footprint, so switching Outline / Pages / Search / Annotations does not visually widen or narrow the sidebar
- Find bar supports `This Document` / `All Open`; `All Open` scopes to PDFs open in the current window, typing alone does not search, first `enter` submits, repeated `enter` / `cmd+g` / `cmd+shift+g` continue match navigation
- Reader navigation keeps the compact Vim-style layer: `j` / `k` page turns, `ctrl+d` / `ctrl+u` half-page scroll, `g` / `shift+g` jump to the document edges
- Compare split in the center reader (`cmd+ctrl+\`); focused pane receives tab switches, `option+click` sends a tab to the other pane
- New windows always start empty and in single-pane mode; relaunch restore also starts single-pane, split stays an explicit in-session toggle
- Multi-window workspaces (`cmd+shift+n`) with per-window tab sets, sidebar, search, and recently-closed state
- Spotlight-style recent-files launcher (`cmd+shift+space`) stays compact, hides traffic lights, supports title/path filtering, `space` multi-select, `enter` open, and an always-visible footer hint
- Optional recent PDFs footer in the left sidebar (toggle in Settings) for one-click reopen
- Swap left and right sidebars on the fly (`cmd+shift+x`) or via Settings
- Theme controls now split into `Mode`, `Light Theme`, and `Dark Theme`
- Light themes support `Normal` / `Rose Pine Dawn`; dark themes support `Normal` / `Rose Pine Moon`
- `i` toggles the current appearance mode between light and dark while keeping your selected light / dark themes
- Rose Pine Dawn warms the PDF page itself into a paper-like tone instead of keeping pure white
- Pink-first highlight workflow (`a` to highlight, with a warm Rose Pine-style inverted mode available in Rose Pine Moon)
- Highlights can carry comments in the right sidebar, and exports include those comments
- Settings now includes a Shortcuts page with capture, clear, restore-default, and conflict rejection
- Settings resizes to fit the current page, so Shortcuts gets a larger window without making General oversized
- Find bar (`cmd+f`), Esc clears search and exits
- All-pages overview (`cmd+shift+o`) with pinch-style zoom
- Demo mode (`cmd+l`) for presentation-style reading: enters full screen, fits the whole page, hides reader chrome, and restores the prior layout on exit
- Immersive mode (`cmd+ctrl+l`) hides sidebars and tab chrome while keeping the current window size
- Per-PDF memory: scale and page persist across launches; sidebar widths follow the current layout config on launch
- Config-driven defaults via `~/Library/Application Support/SlatePDF/config.toml`

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
```

## Ship to your Mac

```sh
just build      # produces build/SlatePDF.app (ad-hoc signed)
just install    # copies the .app to /Applications
just register   # lsregister -f so Finder's Open With sees it
just set-default  # duti -s local.yfff.SlatePDF com.adobe.pdf all
just launch     # open /Applications/SlatePDF.app
```

Full release pipeline:

```sh
just ship       # test → build → install → register → set-default
```

## Configuration

Runtime config lives at `~/Library/Application Support/SlatePDF/config.toml`
and is created on first launch. Edit, then restart SlatePDF.

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

[shortcuts]
# ...
```

- Layout widths apply on launch and restore for all PDFs. Dragging a sidebar
  only changes the current runtime session; restart goes back to the config.
- `mode = "system"` follows the current macOS appearance.
- `light_theme` and `dark_theme` are selected independently, so you can pair
  `Normal` light with `Rose Pine Moon`, or `Rose Pine Dawn` with `Normal`
  dark, without changing the mode model.
- `sidebars_swapped = true` flips the left and right panes — widths travel
  with the panes so your narrow tabs pane stays narrow after the swap.
- `fit_width_on_open` switches fit-to-width on/off for **all currently open
  documents** as soon as you toggle it — any document you've manually zoomed
  stays pinned at your scale.
- Setting a shortcut to `none` clears it completely; SlatePDF will not silently
  fall back to the default binding after restart.

## Keyboard shortcuts

Defined in `[shortcuts]` above. Highlights:

| Action | Shortcut |
|---|---|
| Highlight selection / enter highlight mode | `a` |
| Exit highlight mode | `esc` |
| Toggle light / dark mode | `i` |
| Save annotations | `cmd+s` |
| Copy highlights as Markdown | `cmd+shift+e` |
| Fit width / height | `cmd+0` / `cmd+9` |
| Zoom in / out | `cmd+=` / `cmd+-` |
| Find next / previous match | `cmd+g` / `cmd+shift+g` |
| Show current PDF in Finder | `cmd+r` |
| Half-page down / up | `ctrl+d` / `ctrl+u` |
| Jump to first / last page | `g` / `shift+g` |
| Close tab / window | `cmd+w` |
| Reopen closed tab | `cmd+shift+t` |
| New window | `cmd+shift+n` |
| Quick recent-files launcher | `cmd+shift+space` |
| Toggle sidebar tabs / titlebar tabs | `cmd+shift+1` / `cmd+shift+2` |
| Toggle left / right sidebar | `cmd+b` / `cmd+option+b` |
| Toggle demo mode | `cmd+l` |
| Toggle immersive mode | `cmd+ctrl+l` |
| Toggle compare split | `cmd+ctrl+\` |
| Toggle right sidebar: Outline / Pages | `cmd+shift+l` |
| Swap left and right sidebars | `cmd+shift+x` |
| All-pages overview | `cmd+shift+o` |
| Undo last highlight edit | `cmd+z` |

Standard macOS app/window shortcuts are available too, including `cmd+h`,
`cmd+option+h`, and `cmd+m`.

## Repo layout

```
App/         AppKit entry point, window + split + settings
Core/        Document session store, config, persistence
Features/    Annotation service, exporter, highlight colors, shortcut controller
UI/          CenterReader, LeftTabs, RightOutline, TitlebarTabs
Tests/       Swift Testing + XCTest suites
Resources/   Info.plist, AppIcon.png/.icns
Scripts/     make-app.sh, make-icon.sh
Justfile     Task runner entrypoints
```

## License

Personal use. No redistribution.
