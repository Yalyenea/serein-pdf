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
- Track execution in [TASKS.md](TASKS.md).
- Keep docs in sync when scope or behavior changes.

## Product Rules

- Do not add fallback logic or unnecessary compatibility layers.
- Prefer simple native AppKit solutions over abstraction-heavy designs.
- Keep left tab UI and titlebar tab UI on one shared document/session model.
- Default highlight color: light, low-saturation pink.

## Engineering Rules

- Put temporary files in `.tmp/`.
- Use git, but never commit automatically unless asked.
- Add tests for core state and persistence logic.
- Runtime config file lives at `~/Library/Application Support/SlatePDF/config.toml`; keep docs and defaults aligned with it.
- Prefer validating UI and interaction changes with real PDFs from `~/Downloads` when available.
- Prefer clarity and compactness over premature flexibility.
- Don't use computer-use tool unless i ask.
