# Serein Website

Static HTML, CSS, and JavaScript, with English/Chinese copy and light/dark themes.

- `index.html`: features and download.
- `changelog.html`: release highlights.
- `docs.html`: installation, reading, annotations, shortcuts, and settings.
- `assets/`: shared styles, preference controls, and app icon.

Run `just website` from the repository root and open http://127.0.0.1:4173/.
Run `just website-check` to validate pages, translations, navigation, and local links.

The Website workflow checks pull requests and deploys changes on `main` to GitHub
Pages. Only the public pages and assets are uploaded. Set the Pages custom domain
to `serein.yfff.me`, with a DNS-only Cloudflare CNAME pointing to
`yalyenea.github.io`.
