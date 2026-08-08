# omgstop.org—AI Agent Primer

Written for coding agents. Read this before touching anything; it is the shortest path from clone to correct change.

**What this is.** A static reference site. Each entry ("peeve") is one thing people get wrong, at its own short URL, so you can send someone `omgstop.org/less` instead of arguing. 80 entries, 4 categories.

**Stack.** Eleventy 3.1.6 (ESM), Nunjucks, Sass 1.102 compiled in-process by Eleventy, `@resvg/resvg-js` for social cards, `markdown-it`. Node ≥ 20. No framework, no bundler, no database, no backend, no API, no tests.

## Start here

```bash
npm install
npm run dev      # http://localhost:8066. Do not use another port.
```

| Script | Does |
| --- | --- |
| `npm run dev` | Eleventy `--serve --port=8066`, watches `src/` including SCSS |
| `npm run build` | `gen-peeve-list.js` → `eleventy` → `og/generate.js` |
| `npm run list` | Regenerates the live table in `docs/PEEVE-LIST.md` only |
| `npm run clean` | `rm -rf _site` |
| `npm run deploy` | `utils/deploy/prod.sh` (build + rsync to the NAS) |

`npm run dev` runs **neither** `gen-peeve-list.js` **nor** the OG generator. `/og/*.png` and `/icon-*.png` therefore 404 locally. Expected, not a bug.

## The ten things that will trip you up

1. **SCSS is compiled by Eleventy**, not by a `sass` script—custom extension at `eleventy.config.js:20-42`. There is no `npm run sass`. Do not add one, and do not run `npx sass` against `src/css/`.
2. **`src/static/` maps to the web ROOT**, not `/static`—`eleventy.config.js:44`. `src/static/js/site.js` → `/js/site.js`. It is the only passthrough.
3. **A peeve's `category` must exist in `src/_data/categories.json` or the build throws**—`eleventy.config.js:89-95`. This is deliberate; a typo'd category would otherwise make an unreachable group.
4. **Two URL shapes always exist.** `site.urlStyle` in `src/_data/site.json` only picks which is canonical: `flat` (default) makes `/less` canonical and `/grammar/less` redirect; `nested` swaps them. Flipping it moves the canonical tag, sitemap, OG url and every internal link together.
5. **Slug collisions throw.** `allAliases` claims every slug through `claim()` at `eleventy.config.js:146-153` and errors naming both owners.
6. **Never set `layout`, `tags` or `permalink` in a peeve file.** `src/peeves/peeves.json` sets them for the whole directory.
7. **`docs/PEEVE-LIST.md` is half generated.** Only the block between `<!-- BEGIN:LIVE -->` and `<!-- END:LIVE -->` is rewritten by `utils/gen-peeve-list.js`. The backlog outside those markers is hand-written and preserved byte for byte.
8. **`smartquotes` is tag-aware and shared.** `utils/smartquotes.js` skips anything inside `<...>` so `rule`'s `<em>` survives. Both the page and the OG card use it, so a title cannot come out curly on one and straight on the other.
9. **The listing markup exists twice**—`src/index.njk` and `src/category.njk`. Edit both or they drift.
10. **The light palette exists twice**—`src/css/_tokens.scss` and hardcoded in `utils/og/generate.js:27-31`. Kept in sync by hand.

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
    partials/analytics.njk  gtag, build-mode only
  peeves/
    peeves.json          directory data: layout + tag + computed permalink
    *.md                 80 entries; filename = URL
  css/
    _tokens.scss         Sass vars only; emits no CSS
    style.scss           833 lines, the entire stylesheet
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
  og/generate.js         1200x630 card per peeve → _site/og/<slug>.png
  og/fonts/              bundled so a runner-rendered card matches a Mac-rendered one
  deploy/                local deploy path
.github/workflows/deploy.yml   CI deploy path, same target
```

## Content schema

Verified against all 80 files in `src/peeves/`. **The filename is the URL.**

| Field | Present | Type / notes |
| --- | --- | --- |
| `title` | 80/80 | quoted string |
| `category` | 80/80 | exactly `Grammar`, `Spelling`, `Mangled phrases`, or `Logical fallacies`—unquoted, **required** |
| `order` | 80/80 | int; sorts the listing, then alphabetical |
| `summary` | 80/80 | doubles as meta description and unfurl text |
| `rule` | 80/80 | may carry `<em>`/`<b>`; rendered with `\| smartquotes \| safe` |
| `snark` | 80/80 | the sign-off line, and the last line of the OG card |
| `examples` | 80/80 | list of `{wrong, right, note}`; `note` runs through `mdInline` |
| `aliases` | 56/80 | bare slugs; become redirect stubs **and** dashboard search keys |

There is no `date` (Eleventy uses file ctime), no `tags`, no `draft`, and **no `eyebrow`**—see Known issues.

Snarks deliberately commit the mistake their own entry is about (`/apostrophe` → "Read some book's.", `/straw-man` commits a straw man). That is intentional; do not "fix" them.

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

## Filters and collections (`eleventy.config.js`)

| Name | Line | Purpose |
| --- | --- | --- |
| `prettyUrl` | 49 | strips the trailing slash for display (`/less`) |
| `mdInline` | 55 | `renderInline` for front-matter notes; block renderer would double-wrap |
| `smartquotes` | 56 | curly quotes, tag-aware |
| `isoDate` / `dateOnly` | 60-61 | feed and sitemap |
| `newestPeeveDate` | 62 | max date across a collection |
| `related` | 104 | same-category siblings, rotating window so pages differ |
| `peeves` | 73 | collection, sorted |
| `peevesByCategory` | 79 | collection, grouped; **throws** on unknown category |
| `categoryAliases` | 121 | category hub aliases |
| `allAliases` | 143 | every redirect slug; **throws** on collision |

## Frontend

**CSS**—`src/css/style.scss`, 833 lines, `@use "tokens" as t;`. Strict flat BEM, no nesting, selectors longhand. Sections are `/* --- Name --- */` banners; sub-sections and every media query get `//@ Label`. Colors are CSS custom properties declared once on `:root` and restated under `@media (prefers-color-scheme: dark)`. Breakpoints are **Sass** vars (`t.$bp-md`), usable only in `@media`, never as `var()`.

| Section | Line |
| --- | --- |
| Theme / tokens | 4 |
| Reset / base | 47 |
| Progressive enhancement | 133 |
| Masthead + colophon | 162 |
| Peeve page | 220 |
| Example pairs | 291 |
| Prose | 376 |
| Buttons + navigation | 442 |
| Share | 524 |
| Index (toolbar, listing) | 569 |
| Print | 804 |

**JavaScript**—one file, `src/static/js/site.js` (332 lines), served at `/js/site.js`, loaded `defer` at `base.njk:84`. It is the site's *only* script besides gtag and the one-liner below.

Progressive enhancement is the load-bearing idea: `base.njk:58` adds `js` to `<html>` from a render-blocking inline script, and `.share`/`.toolbar` are `display: none` until then (`style.scss:141-155`). With scripting off both are absent rather than present and dead, and because the class lands before first paint, revealing them costs no layout shift. `[hidden] { display: none !important }` at `style.scss:157` backs the filter's use of the `hidden` attribute.

| Function | Line | Notes |
| --- | --- | --- |
| `fold` | 24 | lowercase + curly→straight quotes. **Length-preserving on purpose**—highlight indices depend on it. No NFD pass for that reason |
| `initShare` | 35 | reads the URL from `link[rel=canonical]` and the title from `meta[property="og:title"]`; nothing is duplicated into the body |
| `flash` | 50 | label swap + `role="status"`; clears the pending timer so repeat clicks cannot strand it |
| `write` / `writeFallback` | 64 / 73 | Clipboard API, then off-screen textarea + `execCommand` when not a secure context. `localhost` **is** secure, so dev takes the first branch |
| `initToolbar` | 117 | builds one folded haystack per item at startup (title + slug + summary + aliases) |
| `paint` | 169 | wraps matches in `<mark>`, rebuilding from cached text and escaping it. The query supplies indices only and is never inserted |
| `reset` | 226 | tests `firstElementChild`, **not** `textContent`—textContent reads identically with or without the `<mark>`s |
| `apply` | 230 | chips AND query; hides empty sections so no heading floats over an empty list |
| `remember` / `restore` | 272 / 281 | `?q=` / `?cat=` via `replaceState`. Not called on load, so campaign params survive |

Filtering runs synchronously per keystroke—80 prebuilt strings, no debounce. Only the `role="status"` count is debounced (400 ms) so the live region does not read a running tally.

## Deployment

Two paths, one target: `/volume1/web/omgstop.org` on the Synology NAS, fronted by Web Station (Nginx) and reached over **Cloudflare Tunnel**—no forwarded HTTP port. Full detail in `docs/DEPLOYMENT.md`.

| | Push to `main` (CI) | `npm run deploy` |
| --- | --- | --- |
| Runs on | GitHub Actions `ubuntu-latest` | your Mac |
| Ships | the committed tree | your working tree, uncommitted included |
| Auth | `SSH_PRIVATE_KEY` secret | ssh-agent or `SSH_KEY_PATH` |
| Gates | `--max-delete=50`, payload check | dirty-tree, on-main, typed confirm, `--max-delete=50` |
| Dry run | dispatch with `dry_run` | `./utils/deploy/prod.sh --dry-run` |

**Neither path hardcodes the target.** Host, port, user and remote path come from `.vscode/sftp.json`—git-tracked on purpose (CI reads it out of the checkout; it holds no credentials). rsync excludes come from `utils/deploy/ignore.json` → `patterns[]`; `protect[]` is CI-only.

**This rsyncs the build output, so anything on the server the build does not produce gets deleted.** Hand-placed files must be added to `protect[]` first. Nothing warns you.

Two non-obvious Nginx facts in `utils/deploy/nginx-user.conf`, both found by testing:

- `try_files $uri $uri/index.html $uri/ =404;`—the idiomatic version 301s `/less` → `/less/`, a wasted hop on the exact URL the site exists to be typed into.
- `expires -1` at **server** level, with assets opting back in. HTML reached through the clean-URL rule is served from inside `location /`, so a `location ~* \.html$` block never matches it. Asset blocks use only `expires` and never `add_header`, because a `location` with its own `add_header` discards every inherited one—which would strip the three security headers from CSS and SVG.

## Secrets reference guide

No secret is committed. Values below are obfuscated; go to the file to read them.

**1. Cloudflare—`.env` (gitignored; `.env.example` is tracked)**

- `CLOUDFLARE_API_TOKEN`—zone-scoped, cache purge only. Optional: without it the deploy still succeeds and skips the purge.
- `CLOUDFLARE_ZONE_ID`—same, optional.
- `CLOUDFLARE_TUNNEL_API_TOKEN`—account-scoped, used only by `utils/deploy/add-tunnel-hostname.sh`. Needs Tunnel Edit + Read, DNS Edit, Zone Read.
- `SSH_KEY_PATH`—optional override; otherwise ssh-agent → `~/.ssh/id_ed25519` → `~/.ssh/id_rsa`.

**2. GitHub repo secrets** (set with `gh secret set NAME < file`)

| Secret | Required | If missing |
| --- | --- | --- |
| `SSH_PRIVATE_KEY` | yes | deploy fails immediately |
| `SSH_KNOWN_HOSTS` | recommended | falls back to trust-on-first-use, with a warning |
| `CLOUDFLARE_API_TOKEN` | no | purge skipped |
| `CLOUDFLARE_ZONE_ID` | no | purge skipped |

**3. Deploy target—`.vscode/sftp.json`** (tracked, no credentials)

- `host` → `na****************co`
- `port` → `337**` (5 digits)
- `username` → `z***`
- `remotePath` → `/volume1/web/omgstop.org`

**4. Not a secret.** `analyticsId` in `src/_data/site.json` is a GA measurement ID—public by design, it ships in the HTML.

**`.gitignore` must keep covering** `_site/`, `node_modules/`, `.env`, and `.vscode/*` **except** `!.vscode/sftp.json`.

## Known issues and debt

1. **`docs/ADDING-A-PEEVE.md` is stale.** It documents an `eyebrow` field that no file uses and that nothing reads, and omits `category` (required), `snark`, and `aliases`. Fix it before pointing anyone at it.
2. **`docs/DEPLOYMENT.md:57` says `omgstop.org` is not registered. It is.** `dig` returns Cloudflare addresses (`172.67.159.252`, `104.21.33.73`) on `boyd/hope.ns.cloudflare.com`. That whole "one-time setup" section needs a pass.
3. **CI → NAS reachability is unverified.** The runner SSHes to port `337**` from GitHub. `docs/DEPLOYMENT.md:162-174` explains why this may never have worked and lists three fixes; a self-hosted runner is the best fit given the tunnel.
4. **Listing markup duplicated**—`src/index.njk` and `src/category.njk`. Extracting a shared partial needs a heading-level parameter (`h3` on the index, `h2` on hubs). Worth doing; deliberately deferred.
5. **Light palette duplicated**—`src/css/_tokens.scss` and `utils/og/generate.js:27-31`.
6. **`npm install` on an older npm strips `libc` fields from `package-lock.json`.** Those matter for Linux CI resolution. If a diff shows only `libc` removals, revert the lockfile.
7. **No tests.** Verification is the build plus a browser. There is no linter wired up either.

## Debugging

| Symptom | Cause |
| --- | --- |
| Build throws `has no entry in categories.json` | Typo'd `category` in a peeve's front matter |
| Build throws `is claimed by both` | Two entries want the same slug—check `aliases` and category slugs |
| `/og/*.png` 404s locally | `npm run dev` skips the OG generator. Run `npm run build` |
| Styles missing after an edit | SCSS compile error—read the Eleventy output, not the browser |
| Search box / share row absent | `js` class never landed. Check the inline script at `base.njk:58` and that `/js/site.js` returns 200 |
| Highlight eats the slug | Something rewrote `.peeve-list__title` instead of the `.peeve-list__label` leaf |
| `/less` 301s instead of 200 | Nginx `user.conf` not installed—`./utils/deploy/install-nginx-conf.sh` |
| rsync exits 25 | `--max-delete=50` fired. Nothing beyond the cap was removed. Read what it wanted to delete |
| Stale content after deploy | Cloudflare purge skipped; its two secrets are unset. Check the workflow log |

## Adding an entry

Drop one Markdown file in `src/peeves/`. Filename = URL. Set all eight fields from the schema table; do not set `layout`, `tags` or `permalink`. Then `npm run dev` and open `http://localhost:8066/<slug>`, and check the dashboard too—`summary` and ordering only show up there.

**Voice** (from `docs/ADDING-A-PEEVE.md`): deadpan with a mouth on it. Flat delivery, occasional profanity, **no exclamation points**. Funny because it is matter-of-fact, not because it is shouting. Keep an entry to a phone screen or two. Lead with the rule. Be right—a correction page with a real error in it is worse than no page. Swear on purpose, not by default. Aim at the mistake, not the person.

## Next

1. Fix `docs/ADDING-A-PEEVE.md` (issue 1)—it is the doc a human is most likely to be handed.
2. Rewrite the setup half of `docs/DEPLOYMENT.md` now that the domain is live (issue 2).
3. Settle CI reachability (issue 3)—a self-hosted runner on the NAS needs nothing inbound.
4. Extract the shared listing partial (issue 4).
5. Consider a linter. There is no lint or format step in the repo today.
