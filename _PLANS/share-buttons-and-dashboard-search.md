# omgstop.org—share buttons, dashboard search/filters, and an agent primer

## Context

Three deliverables in `/Users/ziad/www/omgstop.org`.

**Why share buttons.** The entire premise of the site is that you send someone `omgstop.org/less` instead of arguing with them. The OG and Twitter card metadata at [base.njk:23-39](src/_includes/layouts/base.njk#L23-L39) exists specifically so that link unfurls well. But there is no affordance on the page to actually *get* the link—the reader has to go select the address bar. The one action the site is built around is the one action it doesn't help with.

**Why search and filters.** The dashboard is 80 entries across four server-rendered category sections ([index.njk:13-37](src/index.njk#L13-L37)). Finding a specific one means scrolling and scanning. The natural search key is the thing you'd type—"its", "seperate", "deep seeded"—and there is nowhere to type it. Worse, 56 of the 80 entries carry an `aliases` list (`/it-is` → `its / it's`) that already powers redirects but is never surfaced on the index at all.

**Why a primer.** There is no `_AI_AGENT_PRIMER.md`, so every agent session re-derives the same non-obvious facts: SCSS is compiled by a custom in-process Eleventy extension rather than a `sass` script; `src/static/` maps to the web root, not `/static`; a typo'd `category` throws the build; `docs/ADDING-A-PEEVE.md` documents a field (`eyebrow`) that no longer exists. That reconnaissance is paid for again every session.

## Decisions already made

| Question | Answer |
| --- | --- |
| Share targets | Copy link + `navigator.share`. No third-party networks, no logos, no SDKs |
| Share scope | Peeve pages only—not the index, not the category hubs |
| Filters | Category chips: All + the four categories, with counts |
| Search behaviour | Hide non-matches in place. Grouped DOM stays; no flattening, no dropdown |

## Constraints

- **The site ships zero JavaScript today.** No bundler, no JS passthrough, no `<script>` in [base.njk](src/_includes/layouts/base.njk). This work introduces the first one and sets the precedent.
- **`addPassthroughCopy({"src/static": "."})`** at [eleventy.config.js:44](eleventy.config.js#L44) is the only passthrough and maps to the web **root**. `src/static/js/site.js` → `/js/site.js`, no config change.
- **SCSS compiles in-process** via [eleventy.config.js:20-42](eleventy.config.js#L20-L42). Do not add a `sass` npm script. Breakpoints are Sass vars (`t.$bp-md`), not custom properties; media queries get a `//@ Label` comment.
- **Strict flat BEM** in [style.scss](src/css/style.scss)—no nesting, longhand selectors, `/* --- Name --- */` banners between sections.
- **House voice** for UI copy: deadpan, flat, no exclamation points ([ADDING-A-PEEVE.md:42](docs/ADDING-A-PEEVE.md#L42)).
- **Progressive enhancement.** JS off ⇒ full grouped list intact, no dead controls visible.

## 1 · Progressive-enhancement gate (do this first)

Everything else depends on it. Add one line to the `<head>` of [base.njk](src/_includes/layouts/base.njk), before the stylesheet:

```html
<script>document.documentElement.classList.add("js");</script>
```

Render-blocking by design—it must run before first paint so the JS-only controls are never painted and then removed. That is what makes the share row and the toolbar cost **zero layout shift**. Every new control is `display: none` by default and only shown under `.js`.

Then add before `</body>`:

```html
<script src="/js/site.js" defer></script>
```

**One file, not two.** `/js/site.js` feature-detects (`if (document.querySelector(".share"))`, `if (document.querySelector(".toolbar"))`) and initialises only what is present. One request, cached across the whole site, ~3 KB. Two files would mean a second cache entry to buy nothing.

## 2 · Share row (peeve pages only)

**New file: `src/_includes/partials/share.njk`.** Included from [peeve.njk](src/_includes/layouts/peeve.njk) between the `.peeve__snark` line (peeve.njk:49) and the `nav.related` block (peeve.njk:51).

Markup shape:

```html
<div class="share">
  <p class="share__label">Send it to them</p>
  <div class="share__actions">
    <button type="button" class="share__button" data-copy aria-label="Copy link">
      <span data-copy-label>Copy link</span>
    </button>
    <button type="button" class="share__button" data-share hidden>Share</button>
  </div>
  <span class="share__status visually-hidden" role="status"></span>
</div>
```

**No data attributes for the URL or title.** The JS reads them from metadata that is already correct and already in the head:

- URL ← `document.querySelector('link[rel=canonical]').href`—[base.njk:41](src/_includes/layouts/base.njk#L41), already absolute and already respects `site.urlStyle`.
- Title ← `document.querySelector('meta[property="og:title"]').content`—[base.njk:26](src/_includes/layouts/base.njk#L26), already piped through `smartquotes`.

This avoids duplicating the URL into the body and avoids the straight-vs-curly-quote trap in a `data-` attribute entirely. The partial therefore does not need to recompute `site.url ~ page.url`, which sidesteps the fact that base's `{% set pageUrl %}` is out of scope inside a child layout.

**Copy behaviour.** `navigator.clipboard.writeText(url)`. `http://localhost:8066` *is* a secure context per the Secure Contexts spec, so this works under `npm run dev`—verify it rather than assuming. On rejection or absence, fall back to a temporary off-screen `<textarea>` + `document.execCommand("copy")`.

**Feedback.** The visible label swaps to `Copied.` and reverts after ~2 s; a pending timer is cleared on repeat clicks so rapid clicking can't strand the label. The button carries a fixed `aria-label="Copy link"` so its accessible name never changes, and the confirmation is announced once through the `role="status"` element instead. Swapping the button's own text as the only signal double-announces on some screen readers.

**Share button.** Rendered with `hidden`; JS removes `hidden` only if `navigator.share` exists, so desktop browsers without it never see a dead control. Payload: `{title, url}`. `AbortError` (user dismissed the sheet) is swallowed silently.

**Print.** Add `.share` to the hide list at [style.scss:655-659](src/css/style.scss#L655-L659) alongside `.masthead, .peeve__nav, .skip-link`.

## 3 · Dashboard toolbar

### Template changes

**[index.njk](src/index.njk)**—toolbar inserted after `.home__head`, before the first `section.group`. Inline in `index.njk` rather than a partial: it is used exactly once and inlining keeps the counts next to the loop that produces them.

```html
<div class="toolbar">
  <label class="visually-hidden" for="q">Search</label>
  <input class="toolbar__input" id="q" type="search" autocomplete="off"
         placeholder="Search {{ collections.peeves.length }} of them" />
  <div class="toolbar__chips" role="group" aria-label="Filter by category">
    <button type="button" class="toolbar__chip" data-cat="all" aria-pressed="true">All {{ collections.peeves.length }}</button>
    {% for group in groups %}
    <button type="button" class="toolbar__chip" data-cat="{{ group.slug }}" aria-pressed="false">{{ group.heading }} {{ group.items.length }}</button>
    {% endfor %}
  </div>
  <p class="toolbar__count" role="status"></p>
</div>
```

Then, on the existing loop:

- `section.group` gains `data-cat="{{ group.slug }}"`.
- `li.peeve-list__item` gains `data-aliases="{{ peeve.data.aliases | join(' ') }}"` (empty for the 24 entries without any).
- The bare title text node inside `.peeve-list__title` gets wrapped in `<span class="peeve-list__label">…</span>`.

That last wrap is what makes highlighting safe—see below. Apply the same wrap in [category.njk:28-31](src/category.njk#L28-L31) so the two listings don't drift, even though no toolbar ships there.

**Search index: `data-*` attributes, not a generated `/search.json`.** Title, slug and summary are already in the DOM as text; only `aliases` is missing, and all 80 alias lists total ~1 KB raw (near-free after gzip—the page is 53 KB raw / 6.9 KB gzipped today). A fetched JSON index would add a request, an async path, and a first-keystroke delay to save bytes that compression already recovers.

### Behaviour (`/js/site.js`)

**Normalisation.** Lowercase, then fold typographic quotes to straight (`'`→`'`, `"`/`"`→`"`). Titles render smart-quoted, so `its / it's` contains U+2019 and someone typing `it's` must still match. Both operations preserve length 1:1, which keeps match indices valid against the original string. **No NFD/diacritic stripping**—there is no non-ASCII in this content beyond the quotes, and NFD changes length and breaks the index mapping. Guard anyway: if `folded.length !== original.length`, match but skip highlighting for that element.

**Matching.** Query split on whitespace; every token must appear as a substring of the item's haystack (AND). Haystack = title + slug + summary + aliases. Substring rather than prefix—80 items is small enough that forgiving beats precise. No ranking: results are hidden in place, so display order is the existing `order`-based sort.

**Highlighting.** Only ever applied to pure-text leaf elements: `.peeve-list__label`, `.peeve-list__slug`, `.peeve-list__summary`. Each leaf's original `textContent` is cached in a `WeakMap` on first run. Rewriting builds a fresh string from that cache, HTML-escaping `& < >`, and injects `<mark>` around matched ranges. **The query is only ever used to compute indices, never inserted into HTML**—so there is no injection path. Restoring is `el.textContent = cached`.

Not using the CSS Custom Highlight API: it needs a Firefox version too recent to assume, and the `<mark>` path is a dozen lines with no fallback branch.

**Chips.** `<button aria-pressed>` in a `role="group"`, single-select, `all` active by default. `aria-pressed` is the correct state for a toggle; links would imply navigation and a radio group would need arrow-key roving focus for no gain. Counts are **static totals**, not live—recomputing them on every keystroke reads as jitter.

**Chips × search are ANDed.** Clicking a chip does not clear the query. A `section.group` is visible iff its category is selected **and** at least one of its items survives the query—that avoids the orphaned `<h2>` over an empty `<ul>`.

**URL state.** Reflect `?q=` and `?cat=` via `history.replaceState`, and restore both on load. This site is about sending links; a filtered view that can't be sent is off-premise. Only written when non-default, so the plain `/` URL stays clean.

**Empty state.** Reuse `.home__empty` ([style.scss:612-615](src/css/style.scss#L612-L615)), rendered `hidden` and revealed when the count hits zero. Copy: `Nothing. Either you spelled it wrong or nobody has written it yet.`

**Keyboard.** `/` focuses the input when focus isn't already in a field; `Esc` clears it and returns focus to the page. `type="search"` supplies the native clear affordance in WebKit for free.

**No debounce.** 80 items with pre-cached haystack strings filters in well under a millisecond per keystroke. A debounce here adds perceptible lag to solve nothing.

## 4 · SCSS

Two new banner sections in [style.scss](src/css/style.scss), following the existing `/* --- Name --- */` convention:

- **`.share`**—placed in the existing *Buttons + navigation* section, after `.button` ([style.scss:476-492](src/css/style.scss#L476-L492)), which it should visually echo. Blocks: `.share`, `.share__label` (reuse the `.related__label` uppercase-eyebrow treatment), `.share__actions`, `.share__button`, `.share__status`.
- **`.toolbar`**—at the head of the *Index* section, before `.group` ([style.scss:524](src/css/style.scss#L524)). Blocks: `.toolbar`, `.toolbar__input`, `.toolbar__chips`, `.toolbar__chip` (built on the `.related__list a` 999px pill at [style.scss:455-470](src/css/style.scss#L455-L470)), `.toolbar__count`.

Plus:

- `.share`, `.toolbar` default to `display: none`; `.js .share`, `.js .toolbar` restore them.
- `mark` needs an explicit rule—the UA default yellow is unreadable against the dark palette. Use `background: transparent; color: var(--accent); font-weight: 700`.
- Active chip: `aria-pressed="true"` styled via `.toolbar__chip[aria-pressed="true"]`—state lives in the attribute, not a parallel class.
- Add `.share`, `.toolbar` to the `@media print` hide list ([style.scss:655-659](src/css/style.scss#L655-L659)).
- Sticky toolbar on wider viewports is optional; if added, mark it `//@ Sticky toolbar` and use `t.$bp-md`.

## 5 · `_AI_AGENT_PRIMER.md`

Written **last**, so it documents the finished state including the new JS layer. Repo root, per [AI_AGENT_PRIMER_INSTRUCTIONS.md](/Users/ziad/.claude/docs/AI_AGENT_PRIMER_INSTRUCTIONS.md): agent-first audience, exhaustive in coverage but terse in expression, `path:line` over prose, one-word "none" for anything not applicable rather than padding.

Most of the mandated template collapses for a static site and should say so in a word: **no database, no backend, no API endpoints, no webhooks, no containers, no background jobs, no test suite.** Real content concentrates in:

- **Architecture**—dir tree; the Eleventy data cascade (`peeves.json` → `eleventyComputed.permalink` → `site.urlStyle`); the four collections and the two that *throw* (`peevesByCategory` on an unknown category, `allAliases` on a slug collision via `claim()`).
- **Code structure**—every filter and collection in [eleventy.config.js](eleventy.config.js) with line numbers; [utils/smartquotes.js](utils/smartquotes.js) (tag-aware, shared with the OG generator); [utils/gen-peeve-list.js](utils/gen-peeve-list.js) (rewrites only between `<!-- BEGIN:LIVE -->` markers); [utils/og/generate.js](utils/og/generate.js).
- **Content schema**—the *actual* eight front-matter fields, verified against all 80 files.
- **Deployment**—both paths, condensed from [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md), with the two load-bearing nginx facts (`try_files $uri $uri/index.html $uri/ =404`, server-level `expires -1`) and the rsync flags that exist because something broke.
- **Secrets reference guide**—locations only, values obfuscated: `.env` (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_TUNNEL_API_TOKEN`), the four GitHub repo secrets, `.vscode/sftp.json` (host/user/port `337**`, deliberately tracked, holds no credentials), and a note that `analyticsId` in `site.json` is public by nature and not a secret.

**Critical issues the primer must record**—all found during this exploration:

1. [docs/ADDING-A-PEEVE.md](docs/ADDING-A-PEEVE.md) is stale: documents `eyebrow`, which no file uses; omits `category` (required—the build throws without a match in `categories.json`), `snark`, and `aliases`.
2. [docs/DEPLOYMENT.md:57](docs/DEPLOYMENT.md#L57) states `omgstop.org` is unregistered. Recent commits touch live nginx and Cloudflare tunnel config, so this is likely stale—verify before trusting, don't assert either way.
3. CI→NAS reachability on port `337**` from a GitHub-hosted runner is documented as unverified ([DEPLOYMENT.md:162-174](docs/DEPLOYMENT.md#L162-L174)).
4. `npm run dev` runs neither `gen-peeve-list.js` nor the OG generator, so `/og/*.png` and `/icon-180.png` 404 locally. Expected; not a bug.
5. The listing markup is duplicated between [index.njk:19-31](src/index.njk#L19-L31) and [category.njk:25-37](src/category.njk#L25-L37) and must be edited in lockstep.
6. The light palette is hardcoded a second time in [utils/og/generate.js:27-31](utils/og/generate.js#L27-L31) and has to be kept in sync with [_tokens.scss](src/css/_tokens.scss) by hand.

## Files touched

| File | Change |
| --- | --- |
| `src/_includes/layouts/base.njk` | `.js` class script in head; deferred `/js/site.js` before `</body>` |
| `src/_includes/partials/share.njk` | **new**—share row |
| `src/_includes/layouts/peeve.njk` | include the share partial between snark and related |
| `src/index.njk` | toolbar markup; `data-cat` on sections, `data-aliases` on items, `.peeve-list__label` wrap |
| `src/category.njk` | `.peeve-list__label` wrap only, to stay in sync |
| `src/static/js/site.js` | **new**—share + toolbar, feature-gated |
| `src/css/style.scss` | `.share` and `.toolbar` blocks, `mark`, `.js` gates, print hides |
| `_AI_AGENT_PRIMER.md` | **new** |

Nothing in `eleventy.config.js` or `package.json` changes.

## Deliberately not doing

- **Extracting a shared listing partial** for index/category. It would prevent the duplication in the table above, but it needs a heading-level parameter and is broader than what was asked. Recorded in the primer as a refactor opportunity instead.
- **Search on the category hubs.** Not requested; the hubs are ≤24 items.
- **Third-party share networks.** Explicitly ruled out.

## Verification

```bash
npm run dev   # http://localhost:8066
```

**Share**—on `/its`:

1. Click **Copy link**, paste. Expect exactly `https://omgstop.org/its/` (from the canonical tag, not `localhost`). Label reads `Copied.` and reverts.
2. Click it five times fast—the label must not get stuck.
3. Desktop Chrome/Safari: confirm whether **Share** is present and matches `navigator.share` support. In Safari it should appear and open the sheet.
4. VoiceOver (Cmd+F5): tab to the button, activate, confirm one `Copied.` announcement and that the button is still named "Copy link".
5. Cmd+P → the share row must not appear in the preview.
6. Disable JS (DevTools → Settings → Debugger → Disable JavaScript), reload: the row must be absent, not present-and-inert. Confirm no visible reflow on a normal reload.

**Toolbar**—on `/`:

1. Type `sep` → `separate` survives. Type `seperate` (the alias) → it still survives, proving the alias index works.
2. Type `it's` with a **straight** apostrophe → `its / it's` matches, proving the quote fold.
3. Type `zzz` → all sections gone, empty-state copy shown, count reads 0.
4. Click **Spelling** → only that section. Type into the box with the chip still active → ANDed, chip stays selected.
5. Confirm no section ever renders as a lone heading over an empty list.
6. Confirm `?q=` / `?cat=` appear in the address bar, then reload—state restores.
7. Press `/` from anywhere on the page → input focuses. `Esc` → clears.
8. Check `<mark>` legibility in both light and dark (macOS System Settings → Appearance).
9. Inspect a highlighted title: `.peeve-list__slug` must survive intact—that is the regression the leaf-only rewrite exists to prevent.
10. Disable JS, reload: all 80 entries in four sections, no toolbar.

**Build:**

```bash
npm run build
```

Must complete with no warnings. Confirm `_site/js/site.js` exists and `_site/index.html` still contains all 80 `peeve-list__item` occurrences.
