# SlatePDF

<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="SlatePDF icon"/>
</p>

Native macOS PDF reader — Swift + AppKit + PDFKit. Minimal, flat, compact.

## Features

- Tabbed documents with switchable layouts: left vertical sidebar or titlebar tabs
- Right-side outline pane with PDF bookmarks and current-page counter
- Pink-first highlight workflow (`a` to highlight, `i` to toggle inverted night mode)
- Find bar (`cmd+f`), Esc clears selection and exits
- All-pages overview (`cmd+shift+o`) with pinch-style zoom
- Per-PDF memory: scale, page, sidebar widths persist across launches
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
[reader]
default_display_mode = "single_page_continuous"
fit_width_on_open = false

[annotations]
auto_save = "after_10_minutes"   # or "never"

[layout]
left_sidebar_width = 220
left_sidebar_min_width = 60
left_sidebar_max_width = 520
right_sidebar_width = 320
right_sidebar_min_width = 120
right_sidebar_max_width = 720

[shortcuts]
# ...
```

- Layout defaults apply to **newly opened** PDFs. Dragging a sidebar remembers
  that width per PDF.
- `fit_width_on_open` switches fit-to-width on/off for **all currently open
  documents** as soon as you toggle it — any document you've manually zoomed
  stays pinned at your scale.

## Keyboard shortcuts

Defined in `[shortcuts]` above. Highlights:

| Action | Shortcut |
|---|---|
| Highlight selection / enter highlight mode | `a` |
| Exit highlight mode | `esc` |
| Toggle night mode | `i` |
| Save annotations | `cmd+s` |
| Fit width | `cmd+0` |
| Zoom in / out | `cmd+=` / `cmd+-` |
| Close tab / window | `cmd+w` |
| Reopen closed tab | `cmd+shift+t` |
| Toggle sidebar tabs / titlebar tabs | `cmd+shift+1` / `cmd+shift+2` |
| Toggle left / right sidebar | `cmd+b` / `cmd+option+b` |
| All-pages overview | `cmd+shift+o` |

## Repo layout

```
App/         AppKit entry point, window + split + settings
Core/        Document session store, config, persistence
Features/    Annotation service, highlight colors, shortcut controller
UI/          CenterReader, LeftTabs, RightOutline, TitlebarTabs
Tests/       Swift Testing + XCTest suites
Resources/   Info.plist, AppIcon.png/.icns
Scripts/     make-app.sh, make-icon.sh
Justfile     Task runner entrypoints
```

## License

Personal use. No redistribution.
