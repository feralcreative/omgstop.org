# omgstop.org

A small, foul-mouthed reference for things people keep getting wrong. Each entry lives at its own short URL so you can send someone `omgstop.org/less` instead of having the conversation.

Built with [Eleventy](https://www.11ty.dev/), hosted on the Synology NAS via Web Station, deployed on push to `main`.

## Quick start

```bash
npm install
npm run dev      # http://localhost:8066
```

| Script | What it does |
| --- | --- |
| `npm run dev` | Eleventy dev server on port 8066, watching `src/` including SCSS |
| `npm run build` | Builds the static site into `_site/` |
| `npm run clean` | Deletes `_site/` |
| `npm run deploy` | Runs `utils/deploy/prod.sh` (build + rsync to the NAS) |

## Adding an entry

Drop a Markdown file in `src/peeves/`. The filename becomes the URL: `src/peeves/less.md` is served at `omgstop.org/less`. Full field reference in [docs/ADDING-A-PEEVE.md](docs/ADDING-A-PEEVE.md).

## Layout

```text
src/
  _data/site.json          site name, URL, tagline
  _includes/layouts/
    base.njk               <html>, masthead, footer, meta tags
    peeve.njk              entry page: title, rule box, examples, prose
  peeves/
    peeves.json            directory data: layout + tag + permalink for every entry
    less.md                one entry
  css/
    _tokens.scss           colors, type stacks, breakpoints
    style.scss             everything else
  static/                  copied to the web root verbatim (favicon, robots.txt)
  index.njk                the list of entries
  404.njk
  sitemap.njk
utils/deploy/              local deploy path (see docs/DEPLOYMENT.md)
.github/workflows/         CI deploy path (same target, same config files)
```

## Deploying

Push to `main` and GitHub Actions does it. The local path (`npm run deploy`) still works and hits the same place. Both are documented, including the one-time setup, in [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).
