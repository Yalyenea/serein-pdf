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
- Before every commit, update the relevant documentation in that commit to match its final behavior, configuration, and validation. Keep changes scoped to the work being committed.
- When a similar bug recurs, compare earlier fixes and record the distinct trigger, affected entry points, and regression coverage. For PDF links, consult [docs/reference-link-regressions.md](docs/reference-link-regressions.md) and check destination resolution, column geometry, navigation, and history separately.
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

## Release Process

1. Prepare the version, build number, and changelog, then run `just test` locally. Confirm that both XCTest and Swift Testing finish with passing summaries; a zero exit code with an incomplete test run is insufficient.
2. Run `just dmg` locally to build the release app and package the DMG. Verify the app's version, build number, and code signature, then mount the DMG and check the bundled app.
3. Create and push the release tag only after all local checks pass. Keep GitHub's release tests enabled and avoid using repeated release runs to discover issues that can be checked locally.
4. If GitHub Actions fails, inspect the logs, reproduce the failing conditions locally, and verify the fix before retrying. Rebuild and recheck the release package when application code changes.
5. After publication, download the public DMG and verify its checksum, bundled version, and code signature before reporting the release complete. Install and launch the local app when requested.
