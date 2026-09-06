# Decisions

Why the non-obvious choices were made, and what was rejected. Read this before "simplifying" something that looks odd.

## Eleventy compiles SCSS, not a `sass` script

**Rejected:** a `sass --watch` script running alongside Eleventy, or an IDE extension.

One process, one watcher, one build step. Two compilers means two stylesheets and a drift bug that only shows up in production. There is intentionally no `npm run sass`, and adding one reintroduces the problem it was removed to avoid.

## Both URL shapes always exist

**Rejected:** building only the canonical shape and letting the other 404.

`site.urlStyle` selects which of `/less` and `/grammar/less` is canonical; the other one is always built as a redirect. The whole pitch of the site is that a URL can be typed from memory, and a memory of the wrong shape should still land. Because the choice flows through `eleventyComputed.permalink`, the canonical tag, sitemap, OG url, breadcrumb, and internal links all move together—flipping the value is a one-line change with no follow-up.

## Unknown categories and slug collisions throw the build

**Rejected:** falling back to an "Other" group, or last-write-wins on a duplicate slug.

A typo'd `category` would create a group with no hub page and no breadcrumb, reachable from nowhere and invisible in review. A duplicate slug would silently shadow a real entry. Both fail loudly instead, and `claim()` names both owners so the fix is obvious without a search.

## Snarks commit their own error

`/apostrophe` signs off with "Read some book's." `/straw-man` commits a straw man. This is the joke, it is consistent across the set, and it looks exactly like a bug to anyone reading one entry in isolation. It is not one.

## `fold()` is length-preserving, with no NFD pass

**Rejected:** full Unicode normalization before matching.

The search highlighter folds the haystack, matches against it, and maps the resulting indices back onto the **original** text so the rendered markup keeps its accents and curly quotes. Any transform that changes string length breaks that mapping and the `<mark>` lands in the wrong place. Case folding and quote straightening are both length-preserving; NFD is not.

## The query is never inserted into the DOM

`paint()` rebuilds each label from cached text, escapes it, and uses the query only to compute indices. This is what keeps a `?q=` parameter from becoming an XSS vector on a site whose entire purpose is being linked to by strangers.

## Progressive enhancement over graceful degradation

`.share` and `.toolbar` are `display: none` until an inline, render-blocking script adds `js` to `<html>`. With scripting off they are absent rather than present and inert. The script is inline and render-blocking specifically so the class lands before first paint—an external or deferred script would reveal the controls a frame late and cost a visible layout shift on every page.

## No tests, no linter

**Rejected:** adding a test framework "for completeness".

There is no application logic to test: the build either throws or produces static HTML, and the parts that could regress silently already throw. A screenshot test would be the only meaningful coverage and it costs more to maintain than the site. Verification is `npm run build` plus a browser. Reconsider if real JavaScript logic ever accumulates in `site.js`.

## `try_files $uri $uri/index.html $uri/ =404;`

**Rejected:** the idiomatic `try_files $uri $uri/ =404;`.

The idiomatic form answers `/less` with a **301 to `/less/`**—a wasted round trip on the exact URL the site exists to be typed into. Naming `index.html` explicitly, ahead of the directory test, serves it in place with a 200. Verified in a throwaway `nginx:alpine` container against the real document root, not reasoned about.

## `expires -1` at server level, not in a `location`

HTML reached through the clean-URL rule is served from inside `location /`, so a `location ~* \.html$` block never matches it and pages would inherit whatever the asset rule said. Setting the no-cache default at server level and opting assets back in is the only arrangement that holds.

The asset blocks therefore use **only** `expires` and never `add_header`: a `location` that declares its own `add_header` discards every inherited one, which would quietly strip the three security headers from CSS and SVG.

## `absolute_redirect off` and an authoritative 404

The site sits behind a Cloudflare Tunnel, so an absolute redirect emitted by Nginx can name the wrong scheme or host and cost a second round trip. Turning it off keeps redirects relative.

Web Station injects its own `error_page 404` into the generated server block, and Nginx only inherits `error_page` from an outer level when the inner level defines none. `error_page 404 /404.html;` is therefore restated inside `location /` as well as at server level, so the site's own 404 page wins for every request that 404s.

## The deploy syncs build output, not the repo

**Consequence, stated once because nothing warns you:** anything on the server that the build does not produce gets deleted. A hand-placed file—a domain verification token, a large asset—must be added to `protect[]` in `utils/deploy/ignore.json` **before** the next deploy, not after.

## The rsync flags

Each was added in response to something that actually broke, on a previous project, and carried over deliberately.

- `--checksum` (CI only): every CI build writes fresh mtimes, so rsync's default size-and-mtime comparison re-uploads the entire site on every push. The local script omits it because local mtimes are stable enough.
- `--chmod=D755,F644`: `rsync -a` preserves source permissions, which is wrong for a web server running as a different user. One non-traversable directory 403s everything inside it. macOS now ships openrsync, which has no `--chmod`, so `deploy.sh` feature-detects and leans on a server-side `find`/`chmod` pass instead.
- `--max-delete=50`: a deploy that wants to remove 50+ files is a broken build, not a cleanup. rsync exits 25 and removes nothing beyond the cap.
- `--delete-after`: deletions run after the transfer, so a mid-transfer failure leaves the old site intact rather than half-deleted.
- `concurrency: cancel-in-progress: false`: two rsyncs into one directory corrupt each other, and a killed rsync leaves the server matching no commit. Queueing beats cancelling.

## `.vscode/sftp.json` is git-tracked

The rest of `.vscode/` is ignored. This one file is the single source of host, port, username, and remote path, read by the VS Code SFTP extension, `deploy.sh`, and the CI workflow alike, so the two deploy paths cannot drift. It holds no credentials. If the remote path changes, change it there and nowhere else.

## No DSM password in a file

**Rejected:** putting the DSM password in `.env` so `install-nginx-conf.sh` can run unattended.

That one password owns the whole NAS—22 sites, Surveillance Station, Home Assistant, every container. Trading a rare prompt for a permanent plaintext copy next to a git repo is not a good trade. The sanctioned alternative is a root-owned, argument-free wrapper script with a single `NOPASSWD` sudoers entry, documented in `DEPLOYMENT.md`. Whitelisting `cp`/`chmod`/`chown` directly was also rejected: `NOPASSWD: /bin/cp` is passwordless root with extra steps.

## The listing markup is duplicated on purpose, for now

`src/index.njk` and `src/category.njk` carry the same listing markup. Extracting a shared partial needs a heading-level parameter (`h3` on the index, `h2` on hubs). Worth doing, deliberately deferred—until then, edit both.

## The light palette is duplicated

`src/css/_tokens.scss` and the `BG`/`INK`/`MUTED`/`ACCENT` constants in `utils/og/generate.js`. The card generator is a separate Node process with no access to the compiled CSS, and cards always render light regardless of the viewer's theme—most unfurl surfaces sit on white, and a dark card inside dark chrome disappears. Kept in sync by hand.
