# Architecture

Read before changing `eleventy.config.js`, the URL scheme, or anything that touches collections. Everything here happens at build time; there is no runtime.

## Layout

```text
src/
  _data/
    site.json            name, url, tagline, description, author, analyticsId, urlStyle
    categories.json      4 categories → slug, aliases, heading, title, summary, intro
  _includes/
    layouts/base.njk     <html>, head/meta/OG, masthead, footer, both <script>s
    layouts/peeve.njk    entry page
    partials/share.njk   copy-link + native share row
    partials/schema.njk  JSON-LD
    partials/analytics.njk   gtag, build-mode only
  peeves/
    peeves.json          directory data: layout + tag + computed permalink
    *.md                 80 entries; filename = URL
  css/
    _tokens.scss         Sass vars only; emits no CSS
    style.scss           the entire stylesheet
  static/                copied to the web ROOT
    js/site.js           the site's only JavaScript
    favicon.svg  robots.txt  site.webmanifest
  index.njk              the dashboard (/)
  category.njk           paginated hubs (/grammar, /spelling, /phrases, /fallacies)
  aliases.njk            paginated redirect stubs; bare <html>, does NOT use base.njk
  404.njk  feed.njk  sitemap.njk
utils/
  smartquotes.js         shared by eleventy.config.js and og/generate.js
  gen-peeve-list.js      rewrites the LIVE block of docs/PEEVE-LIST.md
  open-when-ready.js     one-shot browser opener for `npm start`
  og/generate.js         1200x630 card per peeve → _site/og/<slug>.png
  og/fonts/              bundled so a runner-rendered card matches a Mac-rendered one
  deploy/                local deploy path
.github/workflows/deploy.yml   CI deploy path, same target
```

## Data flow

```text
src/peeves/*.md
  └─ peeves.json (directory data) → layout: layouts/peeve.njk
                                  → tags: peeves
                                  → eleventyComputed.permalink ← site.urlStyle
        ↓
  collections.peeves            sorted by order, then title
  collections.peevesByCategory  grouped, joined to categories.json (THROWS on unknown)
  collections.allAliases        every non-canonical URL (claim() THROWS on collision)
        ↓
  index.njk / category.njk / peeve.njk / aliases.njk / feed.njk / sitemap.njk
        ↓
  _site/  ──rsync──▶  /volume1/web/omgstop.org  ──Cloudflare Tunnel──▶  omgstop.org
```

## Filters and collections

All defined in `eleventy.config.js`. Search by name; the file is short.

| Name | Kind | Purpose |
| --- | --- | --- |
| `prettyUrl` | filter | strips the trailing slash for display (`/less`) |
| `mdInline` | filter | `renderInline` for front-matter notes; the block renderer would double-wrap them |
| `smartquotes` | filter | curly quotes, tag-aware |
| `isoDate` / `dateOnly` | filter | feed and sitemap |
| `newestPeeveDate` | filter | max date across a collection |
| `related` | filter | same-category siblings, rotating window so each page shows different neighbours |
| `peeves` | collection | every entry, sorted by `order` then title |
| `peevesByCategory` | collection | grouped and joined to `categories.json`; **throws** on an unknown category |
| `categoryAliases` | collection | category hub aliases (`/logical-fallacies` → `/fallacies`) |
| `allAliases` | collection | every redirect slug; **throws** on a collision, naming both owners |

`peevesByCategory` throwing is deliberate: a typo'd category would otherwise silently create a group with no hub page and no breadcrumb, unreachable from anywhere.

## The alias system

`allAliases` is the single source of every URL that is not a canonical page. It claims slugs in a fixed order so ownership is unambiguous:

1. Category hub slugs from `categories.json`, first, so `/grammar` cannot be taken by an entry.
2. Category hub aliases from `categories.json`.
3. For each peeve, whichever of the flat/nested shapes is **not** canonical.
4. Each peeve's own `aliases`.

`claim()` throws on the first duplicate and names both owners. Every claimed slug renders through `aliases.njk` as the same kind of redirect stub, which is why that template paginates one flat list.

A peeve's `aliases` do double duty: they are redirect stubs **and** search keys in the dashboard toolbar, folded into the haystack alongside title, slug, and summary.

## SCSS compilation

Eleventy compiles SCSS itself through `addTemplateFormats("scss")` plus a custom extension in `eleventy.config.js`, not through a parallel `sass --watch`. Consequences:

- `npm run dev` has one watcher, `npm run build` has one step.
- Partials (leading underscore) return early and never emit their own stylesheet.
- `addDependencies` registers `style.css`'s dependency on its partials so incremental builds pick up a token change.
- A SCSS compile error surfaces in the Eleventy output, not the browser. If styles vanish after an edit, read the terminal.

## Frontend

`src/css/style.scss` is the entire stylesheet. Sections, in order: theme/tokens, reset/base, progressive enhancement, masthead + colophon, peeve page, example pairs, prose, buttons + navigation, share, index (toolbar and listing), print. Find them by their `/* --- Name --- */` banners.

`src/static/js/site.js` is the only script besides gtag and the inline one-liner in `base.njk`. Two features: the share row (`initShare`) and the dashboard toolbar (`initToolbar`). Filtering runs synchronously on every keystroke against 80 prebuilt folded strings, with no debounce; only the `role="status"` count is debounced, at 400 ms, so the live region does not read out a running tally.

`remember` / `restore` sync `?q=` and `?cat=` through `replaceState`. `restore` is deliberately not called on load, so campaign parameters on an inbound link survive.
