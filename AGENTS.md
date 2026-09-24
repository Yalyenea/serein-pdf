# AGENTS.md

## Project

Native macOS PDF reader.

- Stack: `Swift + AppKit + PDFKit`
- UI: minimal, flat, compact
- Tabs: switchable between `verticalSidebar` and `horizontalTitlebar`
- Layout: right outline sidebar, immersive center reader

## Source Of Truth

- Read [PROJECT.md](PROJECT.md) and [README.md](README.md) before coding.
- using justfile for make
- Track open work in [TASKS.md](TASKS.md); open debt in [REVIEW.md](REVIEW.md).
- Completed milestone checklists live under [docs/archive/](docs/archive/) — do not re-expand them into live TASKS.
- Keep docs in sync when scope or behavior changes.
- Multi-theme expansion plan: [docs/theme-presets-plan.md](docs/theme-presets-plan.md).

## Product Rules

- Do not add fallback logic or unnecessary compatibility layers.
- Prefer simple native AppKit solutions over abstraction-heavy designs.
- Keep left tab UI and titlebar tab UI on one shared document/session model.
- Default highlight color: light, low-saturation pink.
- Every new or changed UI component must support all theme presets and live theme switching, including light/dark appearance and custom background colors. Use shared theme colors resolved against the component's effective appearance; refresh text, icons, borders, backgrounds, and active input editors without requiring a page change or reopening the UI. Verify both display and editing states when themes change.

## Engineering Rules

- Use `just run` for routine development and UI testing. Use `just build` only when validating a release bundle or preparing a release.
- Before launching, check for an existing development instance and avoid duplicate launches. Leave the installed `/Applications/Serein.app` instance alone unless asked.
- Do not use `open -n` for routine testing. When opening a PDF in a specific app bundle, use `open -a <app> <pdf>`; passing the app and PDF as separate targets can launch multiple instances.
- Put temporary files in `.tmp/`.
- Use git, but never commit automatically unless asked.
- Add tests for core state and persistence logic.
- Runtime config file lives at `~/Library/Application Support/Serein/config.toml`; keep docs and defaults aligned with it.
- Prefer validating UI and interaction changes with real PDFs from `~/Downloads` when available.
- Prefer clarity and compactness over premature flexibility.
- Don't use computer-use tool unless i ask.
