# AGENTS.md

Operating manual for `omgstop.org`. A static Eleventy site: each entry ("peeve") is one thing people get wrong, published at its own short URL so you can send `omgstop.org/less` instead of having the argument. 80 entries, 4 categories, no framework, no bundler, no database, no backend.

When a change makes anything in this file inaccurate—a command, a path, a convention, a prohibition—update this file in the same change.

## Commands

| Task | Command |
| --- | --- |
| Install | `npm install` |
| Dev server | `npm start` (serves on 8066 and opens a browser once) |
| Dev server, no browser | `npm run start:no-open` or `OPEN_BROWSER=0 npm start` |
| Dev server (raw Eleventy) | `npm run dev` |
| Build | `npm run build` |
| Regenerate `docs/PEEVE-LIST.md` | `npm run list` |
| Clean build output | `npm run clean` |
| Deploy from your machine | `npm run deploy` |
| Deploy dry run | `./utils/deploy/prod.sh --dry-run` |
| Install the Nginx vhost config | `./utils/deploy/install-nginx-conf.sh` |
| Unit tests | none exist |
| Lint / format / typecheck | none wired up |

`npm run build` is `gen-peeve-list.js` → `eleventy` → `og/generate.js`. `npm start` and `npm run dev` run **neither** the peeve-list generator **nor** the OG generator, so `/og/*.png` and `/icon-*.png` 404 locally. That is expected.

Port 8066 is this project's port. Do not run it on another one, and do not start a second instance—if 8066 is taken the server is already running, so kill it and restart on 8066.

## Definition of done

1. `npm run build` exits 0 with no thrown errors and no new warnings.
2. Open the affected pages on `http://localhost:8066` under `npm start`. For a content change that means the entry page **and** the dashboard, since `summary` and ordering only render on the dashboard.
3. If you touched `src/peeves/`, `src/_data/categories.json`, or `utils/gen-peeve-list.js`, run `npm run list` and commit the resulting `docs/PEEVE-LIST.md` diff.
4. If you touched `utils/deploy/nginx-user.conf`, say so explicitly in the handover. It does not ship with a normal deploy; it needs `install-nginx-conf.sh` and a DSM password.

Not required: there is no test suite, no linter, and no typecheck. Do not invent one, do not add a test framework, and do not report "tests pass". Verification here is the build plus a browser.

## Prohibitions

- **Never commit or deploy without explicit permission.** Both are the user's call, every time.
- **Never hand-edit `_site/`.** It is build output, gitignored, and `npm run build` regenerates it.
- **Never hand-edit the block between `<!-- BEGIN:LIVE -->` and `<!-- END:LIVE -->` in `docs/PEEVE-LIST.md`.** `utils/gen-peeve-list.js` rewrites it. Everything outside those markers is hand-written and preserved byte for byte—edit the backlog there freely.
- **Never set `layout`, `tags`, or `permalink` in a peeve's front matter.** `src/peeves/peeves.json` sets them for the whole directory; overriding one file is how the URL scheme quietly stops being consistent.
- **Never add a `sass` npm script or run `npx sass` against `src/css/`.** Eleventy compiles SCSS in-process through a custom extension in `eleventy.config.js`. A second compiler produces a second stylesheet and they drift.
- **Never add a bundler, framework, CSS-in-JS, or a second JavaScript file** without asking. The site is one 332-line script and one stylesheet on purpose.
- **Never remove an rsync flag from `utils/deploy/`.** `--checksum`, `--chmod=D755,F644`, `--max-delete=50`, and `--delete-after` each exist because something broke without them. Rationale is in `docs/DEPLOYMENT.md`.
- **Never hand-place a file in the web root without adding its pattern to `protect[]` in `utils/deploy/ignore.json` first.** The deploy rsyncs build output, so anything the build does not produce gets deleted, silently.
- **Never "fix" a snark that commits the error its own entry is about.** `/apostrophe` signs off with "Read some book's." and `/straw-man` commits a straw man. That is deliberate.
- **Never put a secret in `.vscode/sftp.json`.** It is git-tracked on purpose—CI reads the deploy target out of the checkout—and the repo is public.

## Architecture

Entry is `eleventy.config.js`, which owns every filter, collection, and the SCSS extension. There is no application code and no runtime; everything happens at build time.

Build path, in order:

1. `utils/gen-peeve-list.js` reads `src/peeves/*.md` and rewrites the LIVE block of `docs/PEEVE-LIST.md`.
2. Eleventy reads `src/`. `src/peeves/peeves.json` is directory data: it applies `layouts/peeve.njk`, the `peeves` tag, and an `eleventyComputed.permalink` that branches on `site.urlStyle`.
3. Collections build: `peeves` (sorted by `order`, then title), `peevesByCategory` (joined to `categories.json`, **throws** on an unknown category), `categoryAliases`, and `allAliases` (every redirect slug; `claim()` **throws** on a collision, naming both owners).
4. Templates render: `index.njk` (dashboard), `category.njk` (hubs), `peeve.njk`, `aliases.njk` (redirect stubs, bare `<html>`, does **not** use `base.njk`), `feed.njk`, `sitemap.njk`, `404.njk`.
5. `src/static/` is passthrough-copied to the web **root**, not to `/static`. It is the only passthrough.
6. `utils/og/generate.js` renders a 1200×630 card per peeve into `_site/og/`, plus the icons.
7. `_site/` rsyncs to `/volume1/web/omgstop.org` on the NAS, served by Web Station Nginx, reached over Cloudflare Tunnel.

Dependency direction: `utils/smartquotes.js` is shared by `eleventy.config.js` and `utils/og/generate.js` so a title cannot come out curly on the page and straight on the card. Nothing else is shared between the build and the generators.

**Both URL shapes always exist.** `site.urlStyle` in `src/_data/site.json` only picks which is canonical. `flat` (the current value) makes `/less` canonical and `/grammar/less` a redirect; `nested` swaps them. Flipping it moves the canonical tag, sitemap entry, OG url, breadcrumb, and every internal link together—there is nothing else to change.

Deeper: [docs/architecture.md](docs/architecture.md).

## Peeve front matter

The filename is the URL. `src/peeves/less.md` is served at `omgstop.org/less`. All eight fields below are present in all 80 files; treat them all as required except `aliases`.

| Field | Type / notes |
| --- | --- |
| `title` | quoted string |
| `category` | exactly `Grammar`, `Spelling`, `Mangled phrases`, or `Logical fallacies`, unquoted. Must match a key in `src/_data/categories.json` or the build throws |
| `order` | int; sorts the listing, then alphabetical |
| `summary` | doubles as the meta description and the unfurl text |
| `rule` | may carry `<em>`/`<b>`; rendered `\| smartquotes \| safe` |
| `snark` | the sign-off line, and the last line of the OG card |
| `examples` | list of `{wrong, right, note}`; `note` runs through `mdInline` |
| `aliases` | bare slugs; become redirect stubs **and** dashboard search keys |

There is no `date` field (Eleventy uses file ctime), no `tags`, and no `draft`. There is **no `eyebrow` field**—`peeve__eyebrow` is a CSS class fed from `categories.json`, and `docs/ADDING-A-PEEVE.md` is stale on this point. Do not add `eyebrow` to a file; nothing reads it.

Voice, when writing an entry: deadpan with a mouth on it. Flat delivery, occasional profanity, no exclamation points. Lead with the rule. Keep it to a phone screen or two. Be right—a correction page with an error in it is worse than no page. Aim at the mistake, not the person.

## Conventions

- **SCSS** lives in `src/css/style.scss` with `@use "tokens" as t;`. Strict flat BEM, no nesting, selectors written longhand. Section banners are `/* --- Name --- */`; sub-sections and **every** media query get `//@ Label` above them.
- **Colors are CSS custom properties**, declared once on `:root` and restated under `@media (prefers-color-scheme: dark)`. Only use variables that are actually defined in `_tokens.scss`.
- **Breakpoints are Sass variables** (`t.$bp-md`), usable only inside `@media`. They are not available as `var()`.
- `src/css/_tokens.scss` emits no CSS. It is variables only.
- **JavaScript** is one file, `src/static/js/site.js`, served at `/js/site.js`, loaded `defer` from `base.njk`. ES5-flavoured `function` declarations inside an IIFE, no modules, no build step.
- **Progressive enhancement is load-bearing.** A render-blocking inline script in `base.njk` adds `js` to `<html>`; `.share` and `.toolbar` are `display: none` until then, so with scripting off they are absent rather than present and dead. Because the class lands before first paint, revealing them costs no layout shift.
- **Prose uses the Oxford comma** and tight em dashes (`word—word`, never spaced). This applies to entry copy, docs, and commit messages alike.
- Markdown docs: never hard-wrap prose, always give fenced blocks a language, use `<!--| PAGE-BREAK -->` rather than `---` for section breaks.

## Gotchas

- **The listing markup exists twice**, in `src/index.njk` and `src/category.njk`. Edit both or they drift. Extracting a shared partial needs a heading-level parameter (`h3` on the index, `h2` on hubs); it has been deliberately deferred.
- **The light palette exists twice**, in `src/css/_tokens.scss` and hardcoded near the top of `utils/og/generate.js` (`BG`, `INK`, `MUTED`, `ACCENT`). Kept in sync by hand. Change one, change the other.
- **`fold()` in `site.js` is length-preserving on purpose.** It lowercases and straightens curly quotes and does nothing else—no NFD normalization—because the search highlighter maps match indices from the folded string back onto the original text.
- **`paint()` never inserts the query into the DOM.** It rebuilds from cached text and escapes it; the query supplies indices only. Keep it that way.
- **`reset()` tests `firstElementChild`, not `textContent`.** `textContent` reads identically with and without the `<mark>` wrappers, so a `textContent` check silently never resets.
- **`initShare()` reads the URL from `link[rel=canonical]` and the title from `meta[property="og:title"]`.** Nothing is duplicated into the body for it. Do not add data attributes to feed it.
- **`mdInline`, not `render`, for front-matter notes.** Notes already sit inside a `<p>`; the block renderer wraps them in a second one.
- **`smartquotes` is tag-aware**—it skips anything inside `<...>`, which is why `rule` can carry `<em>` without the attributes getting curled.
- **`npm install` on an older npm strips `libc` fields from `package-lock.json`.** Those matter for Linux CI resolution. If a lockfile diff shows only `libc` removals, revert it.
- **`docs/DEPLOYMENT.md` still says `omgstop.org` is not registered. It is**—the domain resolves through Cloudflare on `boyd`/`hope.ns.cloudflare.com`. Treat the "One-time setup" section's step 1 as obsolete; the rest of that section is still accurate.
- **CI → NAS reachability is unverified.** The runner SSHes to the NAS over a forwarded port while all HTTP ingress runs over Cloudflare Tunnel, which is what people use to avoid forwarding ports. If CI fails with an empty `known_hosts`, that is why; `docs/DEPLOYMENT.md` lists three fixes.

More symptoms and causes: [docs/debugging.md](docs/debugging.md).

## Credentials

No secret value belongs in this file, in `docs/`, or in any commit. `.env` is gitignored; `.env.example` is the canonical list of keys.

| Variable | Source | Notes |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | `.env`, and a repo secret | Zone-scoped, cache purge only. Optional—without it the deploy succeeds and skips the purge |
| `CLOUDFLARE_ZONE_ID` | `.env`, and a repo secret | Same, optional |
| `CLOUDFLARE_TUNNEL_API_TOKEN` | `.env` | Account-scoped, used only by `utils/deploy/add-tunnel-hostname.sh`. Needs Tunnel Edit + Read, DNS Edit, Zone Read |
| `SSH_KEY_PATH` | `.env` | Optional override; otherwise ssh-agent → `~/.ssh/id_ed25519` → `~/.ssh/id_rsa` |
| `SSH_PRIVATE_KEY` | GitHub repo secret | Required in CI. Deploy fails immediately without it. Use a dedicated deploy key, never a personal one |
| `SSH_KNOWN_HOSTS` | GitHub repo secret | Recommended. Without it CI falls back to trust-on-first-use with a warning |

Set repo secrets by piping on stdin (`gh secret set NAME < file`) so nothing reaches shell history. `analyticsId` in `src/_data/site.json` is a GA measurement ID—public by design, it ships in the HTML, and it is not a secret.

`.gitignore` must keep covering `_site/`, `node_modules/`, `.env`, and `.vscode/*` **except** `!.vscode/sftp.json`. Never read a file matching those patterns into a commit, a log, or a chat response.

**This repository is public.** `.vscode/sftp.json` and `docs/DEPLOYMENT.md` disclose the NAS hostname, SSH port, username, and remote path in plaintext, deliberately, because CI reads the target out of the checkout. They hold no credentials, but do not add anything further to them.

## Commit and PR conventions

- Conventional Commits: `type(scope): subject`, imperative mood. Types in use here: `feat`, `fix`, `chore`, `refactor`, `docs`, `style`, `content`.
- Work on `main`. Pushing to `main` triggers the CI deploy, so a push is a release.
- Stage and commit as one chained command: `git add -A && git commit -m "..."`.
- Never add AI co-author attribution—no `Co-Authored-By`, no generated-with footer, in commits or PR bodies.
- Never commit `_site/`, `node_modules/`, or `.env`.

## Deep-dive index

- [docs/architecture.md](docs/architecture.md)—collections, filters, the alias system, data flow. Read before changing `eleventy.config.js` or the URL scheme.
- [docs/ADDING-A-PEEVE.md](docs/ADDING-A-PEEVE.md)—field reference and house voice for a new entry. Stale on `eyebrow`; the front-matter table above supersedes it.
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)—both deploy paths, one-time setup, the Nginx config, the rsync flags and why each exists.
- [docs/decisions.md](docs/decisions.md)—why the non-obvious choices were made and what was rejected. Read before "simplifying" something that looks odd.
- [docs/debugging.md](docs/debugging.md)—symptom-to-cause table for build, style, script, and serving failures.
- [docs/PEEVE-LIST.md](docs/PEEVE-LIST.md)—every published entry plus the hand-written backlog. Half generated; see Prohibitions.
