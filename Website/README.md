# Serein Website

Local static website for Serein. It is intentionally dependency-light: plain
HTML, CSS, and JavaScript.

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

The check verifies the required website files, local asset references, and the
current release link. It does not configure GitHub Pages or write deployment
metadata.
