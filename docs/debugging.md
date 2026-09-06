# Debugging

Symptom to cause. Deploy-specific failures have their own table in [DEPLOYMENT.md](DEPLOYMENT.md); this one covers the build, the styles, the script, and serving.

## Build

| Symptom | Cause |
| --- | --- |
| `Category "…" has no entry in src/_data/categories.json` | Typo'd `category` in a peeve's front matter. It must be exactly `Grammar`, `Spelling`, `Mangled phrases`, or `Logical fallacies` |
| `URL "/x" is claimed by both … and …` | Two entries want the same slug. The message names both owners—check `aliases` in each, and the category slugs in `categories.json` |
| Build succeeds but an entry is missing from the dashboard | The file is not in `src/peeves/`, so `peeves.json` never applied the `peeves` tag to it |
| An entry sorts to the bottom | No `order`, or a duplicate `order`. Ties fall back to alphabetical by title |
| `docs/PEEVE-LIST.md` is out of date | `npm run dev` does not run the generator. Run `npm run list` (or a full `npm run build`) |
| A hand-written backlog note vanished from `PEEVE-LIST.md` | It was inside the `BEGIN:LIVE`/`END:LIVE` markers. Only content outside them survives regeneration |

## Local dev

| Symptom | Cause |
| --- | --- |
| `/og/*.png` or `/icon-*.png` 404s | `npm start` and `npm run dev` skip the OG generator. Run `npm run build` |
| Port 8066 already in use | The dev server is already running. Kill it and restart on 8066—never fall back to another port |
| Browser did not open | `OPEN_BROWSER=0` is set, or the server took longer than 15s. `utils/open-when-ready.js` prints the URL and exits rather than hanging |
| Two browser tabs open per save | Something moved the opener inside the server process. It must run alongside it, once, and exit |
| Styles missing after a SCSS edit | A Sass compile error. It surfaces in the Eleventy terminal output, not the browser console |
| A token change did not take effect | Restart the dev server. `addDependencies` covers partials, but a change to the extension itself in `eleventy.config.js` needs a restart |

## Frontend

| Symptom | Cause |
| --- | --- |
| Search box or share row is absent | The `js` class never landed on `<html>`. Check the inline script in `base.njk` and that `/js/site.js` returns 200 |
| Share button copies the wrong URL | `initShare` reads `link[rel=canonical]`. A page rendering the wrong canonical is the actual bug |
| Highlight eats the slug in a listing row | Something rewrote `.peeve-list__title` instead of the `.peeve-list__label` leaf. `paint` must only touch leaf text nodes |
| Highlight lands a character or two off | Something added a non-length-preserving transform to `fold()`. Match indices are mapped back onto the original string |
| Filter leaves an empty category heading floating | `apply()` hides sections with no visible items; a new listing section needs the same treatment |
| Screen reader reads a running tally while typing | The 400 ms debounce on the `role="status"` count was removed or bypassed |
| Campaign parameters stripped on load | `restore()` is being called on load. It is deliberately not, so inbound `?utm_*` survives |

## Serving

| Symptom | Cause |
| --- | --- |
| `/less` 301s instead of returning 200 | The Nginx `user.conf` is not installed. Run `./utils/deploy/install-nginx-conf.sh` |
| DSM's default 404 page instead of the site's | Same cause, or `error_page 404 /404.html;` was removed from inside `location /`—Web Station's own `error_page` wins otherwise |
| CSS and SVG come back without the security headers | An asset `location` block grew an `add_header`, which discards every inherited one. Asset blocks may use `expires` only |
| HTML is being cached | The `expires -1` default moved off the server block into a `location ~* \.html$`, which never matches a clean URL |
| Stale content after a deploy | The Cloudflare purge was skipped because `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ZONE_ID` are unset. Check the workflow log for the warning |
| A file never appears on the server | Check it against **both** arrays in `utils/deploy/ignore.json`. `protect[]` blocks uploads as well as deletions |
| A hand-placed file disappeared | The deploy syncs build output and deletes anything else. It needed a `protect[]` pattern first |

## Health checks

```bash
npm run build                      # the only real verification step
curl -sI https://omgstop.org/less  # expect 200, not 301
dig +short omgstop.org             # expect Cloudflare addresses
./utils/deploy/prod.sh --dry-run   # what a deploy would change, and delete
```
