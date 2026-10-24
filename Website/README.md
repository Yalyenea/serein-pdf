# Serein Website

Static HTML, CSS, and JavaScript, with English/Chinese copy and light/dark themes.

- `index.html`: features, screenshots, installation questions, and download.
- `assets/`: styles, language and theme controls, fonts, and screenshots.

Run `just website` from the repository root and open http://127.0.0.1:4173/.
Run `just website-check` to validate pages, translations, navigation, and local links.

The Website checks workflow validates pull requests and changes on `main`.
Cloudflare Workers serves the site at https://serein.yfff.me/ using
`wrangler.website.jsonc`. Publish with
`npx wrangler@4.152.0 deploy --config wrangler.website.jsonc`.
`Website/.assetsignore` limits uploads to `index.html` and `assets/`.
Release notes and shortcuts link to GitHub.
