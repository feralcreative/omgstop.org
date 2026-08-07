# Adding an entry

Create one Markdown file in `src/peeves/`. Everything else is automatic: the URL, the layout, the listing on the home page, the sitemap entry, the social preview.

**The filename is the URL.** `src/peeves/reply-all.md` is served at `omgstop.org/reply-all`. Keep slugs short, lowercase, and typeable from memory, because the entire point is that you can type the URL into Slack without looking it up.

## The shape of a file

```markdown
---
title: "less vs. fewer"
eyebrow: Grammar
order: 1
summary: "One is for things you count. The other is for things you measure."
rule: "If you can count them, it's <em>fewer</em>."
examples:
  - wrong: "We need less meetings."
    right: "We need fewer meetings."
    note: "Meetings come in whole units."
---

## A section heading

Body copy goes here, in Markdown.
```

## Front matter fields

| Field | Required | What it does |
| --- | --- | --- |
| `title` | yes | The `<h1>`, the browser tab, the link preview title, the label in the home-page list |
| `summary` | recommended | One or two sentences under the title. Doubles as the meta description and the Slack unfurl text, so write it like a subhead, not a teaser |
| `rule` | recommended | The tl;dr in the bordered box. HTML is allowed and `<em>` renders in the accent color, so mark the operative words with it |
| `eyebrow` | no | Small uppercase category above the title, e.g. `Grammar`, `Meetings`, `Email` |
| `order` | no | Sort position on the home page. Unset sorts to the bottom, then alphabetically |
| `examples` | no | A list of `wrong` / `right` / `note` triples, rendered as struck-through-vs-correct pairs |

Do not set `layout`, `tags`, or `permalink` in a file. `src/peeves/peeves.json` sets those for every file in the directory, and overriding one of them in a single file is how the URL scheme quietly stops being consistent.

## Writing the thing

The house voice is deadpan with a mouth on it. Flat delivery, occasional profanity, no exclamation points. It is funny because it is matter-of-fact, not because it is shouting.

- **Keep it short.** An entry is a rule box, a few examples, and maybe 200 words. If it runs past a phone screen or two, cut. Nobody who was just told they're wrong reads to the bottom.
- **Lead with the rule, not the history.** Most people read the box and leave. That is a success.
- **Swear on purpose, not by default.** One or two land. Every other sentence reads as trying too hard and buries the actual point. Put them where the entry turns, not in the summary.
- **Be right.** A correction page with an error in it is worse than no page. If a rule has real exceptions, list them before someone else does. `/less` compresses them into four bullets rather than dropping them, because those bullets are exactly what a cornered coworker reaches for.
- **Concede what is actually true.** Where the "rule" is really a convention, say so. It costs nothing and it is the difference between a reference and a rant.
- **Aim at the mistake, not the person.** "This is wrong and here's why" survives being forwarded. "You're an idiot" does not, and you are the one who sent the link.

## Checking it

```bash
npm run dev
```

Then open `http://localhost:8066/your-slug`. Check the home page too, since the summary and ordering only show up there.

Before pushing, worth a look:

- Does the `rule` box stand alone if someone reads nothing else?
- Does the `summary` read well as a Slack preview, out of context and without the title?
- Do the examples wrap cleanly on a phone? They are monospaced, so long ones get wide.
