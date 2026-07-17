# Serein Website

Local static product site for Serein. Dependency-light: plain HTML, CSS, and
JavaScript — no build step.

Design direction follows an editorial / archive “knowledge tool” pattern:
warm paper base, serif display type, hairline brand mark, grain texture,
staggered rise/reveal, light/dark theme, and EN/中文 copy.

## Preview

From the repository root:

```sh
just website
```

Then open:

```text
http://127.0.0.1:4173/
```

## Check

```sh
just website-check
```

The check verifies required website files, local asset references, and the
current release link. It does not configure GitHub Pages or write deployment
metadata.

## Structure

| Path | Role |
|---|---|
| `index.html` | Hero, feature bands, alternating rows, download, compact docs |
| `assets/styles.css` | Design tokens + layout |
| `assets/main.js` | Theme, language, scroll reveal, path copy |
| `assets/serein-reader.png` | Product screenshot |
| `assets/app-icon.png` | Favicon / footer mark |

## Follow-up

Planned under **M13.1** in [TASKS.md](../TASKS.md): replace editorial placeholder cards with real feature screenshots, optional GitHub Pages deploy, and EN/中文 copy pass. Skeleton is done; polish when assets are ready.
