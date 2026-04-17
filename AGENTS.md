# AGENTS.md

## Project

Native macOS PDF reader.

- Stack: `Swift + AppKit + PDFKit`
- UI: minimal, flat, compact
- Tabs: switchable between `verticalSidebar` and `horizontalTitlebar`
- Layout: right outline sidebar, immersive center reader

## Source Of Truth

- Read [PROJECT.md](PROJECT.md) before coding.
- Track execution in [TASKS.md](TASKS.md).
- Keep docs in sync when scope or behavior changes.

## Product Rules

- Do not add fallback logic or unnecessary compatibility layers.
- Prefer simple native AppKit solutions over abstraction-heavy designs.
- Keep left tab UI and titlebar tab UI on one shared document/session model.
- Default highlight color: light, low-saturation pink.
- `a`: highlight now, or enter highlight mode if no selection.
- `Esc`: exit highlight mode.
- `i`: toggle inverted night mode.
- `Cmd+S`: save annotations to the source PDF.
- Annotation edits should mark dirty state first, not save immediately.
- Auto-save policy defaults to `10 min` and must support `never`.

## Engineering Rules

- Put temporary files in `.tmp/`.
- Use git, but never commit automatically unless asked.
- Add tests for core state and persistence logic.
- Prefer clarity and compactness over premature flexibility.

## Initial Focus

Build the smallest correct loop first:

1. app skeleton
2. split view window
3. PDF open + render
4. shared document store
5. switchable tab presentation
6. outline sidebar
