#!/usr/bin/env node
// Renders a 1200x630 preview card per peeve into _site/og/<slug>.png.
//
// Runs after Eleventy (see the `build` script) because it reads the same front
// matter Eleventy does and writes into the finished output directory.
//
// Fonts are bundled in utils/og/fonts rather than loaded from the system:
// resvg would otherwise pick whatever the host happens to have, and a card
// rendered on a GitHub runner would not match one rendered on a Mac.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";
import { smartquotes } from "../smartquotes.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const PEEVES = path.join(ROOT, "src", "peeves");
const OUT = path.join(ROOT, "_site", "og");
const FONTS = path.join(ROOT, "utils", "og", "fonts");

const W = 1200;
const H = 630;

// Must track the light palette in src/css/_tokens.scss. Cards always render
// light: most unfurl surfaces sit on a white background, and a dark card with a
// dark chrome around it disappears.
const BG = "#faf9f6";
const INK = "#17171a";
const MUTED = "#6a655e";
const ACCENT = "#d92d20";

const esc = (s) =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

// Strip the HTML that `rule` carries and the Markdown that summaries may.
const plain = (s) =>
  String(s ?? "")
    .replace(/<[^>]+>/g, "")
    .replace(/[*_`]/g, "")
    .trim();

function frontMatter(raw) {
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!m) return null;
  const data = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z_][\w-]*):\s*(.+)$/);
    if (!kv) continue;
    if (!(kv[1] in data)) {
      data[kv[1]] = kv[2].replace(/^"(.*)"$/, "$1").replace(/\\"/g, '"');
    }
  }
  return data;
}

// resvg has no text layout engine to consult, so lines are measured here with
// a per-character width approximation. Inter Display Black is fairly uniform,
// which keeps the estimate close enough that nothing overflows the card.
function wrap(text, maxChars) {
  const words = String(text).split(/\s+/);
  const lines = [];
  let line = "";
  for (const w of words) {
    const candidate = line ? `${line} ${w}` : w;
    if (candidate.length > maxChars && line) {
      lines.push(line);
      line = w;
    } else {
      line = candidate;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function card({ title, summary, category, snark }) {
  title = smartquotes(title);
  summary = smartquotes(summary);
  snark = smartquotes(snark || "");

  // Title size steps down as it gets longer so long entries stay on the card.
  const titleLines = wrap(title, title.length > 28 ? 22 : 18);
  const titleSize = titleLines.length > 2 ? 74 : titleLines.length > 1 ? 90 : 104;
  const titleLead = titleSize * 1.04;

  // Fixed start, growing downward — an earlier version centred the title block,
  // which pushed tall titles up into the category label.
  const TITLE_TOP = 274;
  const titleBottom = TITLE_TOP + (titleLines.length - 1) * titleLead;

  // A three-line title leaves room for one line of rule, not three.
  const maxSummaryLines = titleLines.length >= 3 ? 1 : titleLines.length === 2 ? 2 : 3;
  const summaryLines = wrap(summary, 58).slice(0, maxSummaryLines);
  const summaryTop = titleBottom + 74;
  const summaryBottom = summaryTop + (summaryLines.length - 1) * 46;

  // The snark closes the card, but only if the title and rule left room. Cards
  // are built from real content of varying length; silently overlapping is
  // worse than silently omitting.
  const SNARK_Y = H - 118;
  const showSnark = Boolean(snark) && summaryBottom + 66 <= SNARK_Y;

  const titleTspans = titleLines
    .map((l, i) => `<tspan x="80" dy="${i === 0 ? 0 : titleLead}">${esc(l)}</tspan>`)
    .join("");

  const summaryTspans = summaryLines
    .map((l, i) => `<tspan x="80" dy="${i === 0 ? 0 : 46}">${esc(l)}</tspan>`)
    .join("");

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <rect width="${W}" height="${H}" fill="${BG}"/>
  <rect x="0" y="0" width="18" height="${H}" fill="${ACCENT}"/>

  <text x="80" y="120" font-family="Inter Display" font-weight="900" font-size="32" letter-spacing="4" fill="${MUTED}">OMG</text>
  <text x="192" y="120" font-family="Inter Display" font-weight="900" font-size="32" letter-spacing="4" fill="${ACCENT}">STOP</text>

  <text x="80" y="206" font-family="Inter" font-weight="400" font-size="24" letter-spacing="3.4" fill="${ACCENT}">${esc(
    String(category || "").toUpperCase()
  )}</text>

  <text x="80" y="${TITLE_TOP}" font-family="Inter Display" font-weight="900" font-size="${titleSize}" fill="${INK}" letter-spacing="-2">${titleTspans}</text>

  <text x="80" y="${summaryTop}" font-family="Inter" font-weight="400" font-size="34" fill="${MUTED}">${summaryTspans}</text>
${
  showSnark
    ? `\n  <text x="80" y="${SNARK_Y}" font-family="Inter Display" font-weight="900" font-size="34" fill="${ACCENT}" letter-spacing="-0.5">${esc(
        wrap(snark, 52)[0]
      )}</text>`
    : ""
}
  <text x="80" y="${H - 52}" font-family="Inter" font-weight="400" font-size="26" fill="${MUTED}">omgstop.org</text>
</svg>`;
}

const fontFiles = fs
  .readdirSync(FONTS)
  .filter((f) => f.endsWith(".ttf"))
  .map((f) => path.join(FONTS, f));

if (!fontFiles.length) {
  console.error("No fonts in utils/og/fonts — cards would render in a fallback face.");
  process.exit(1);
}

fs.mkdirSync(OUT, { recursive: true });

const files = fs.readdirSync(PEEVES).filter((f) => f.endsWith(".md"));
let written = 0;

for (const file of files) {
  const data = frontMatter(fs.readFileSync(path.join(PEEVES, file), "utf8"));
  if (!data) continue;
  const slug = file.replace(/\.md$/, "");

  const svg = card({
    title: plain(data.title),
    // The rule is the sharper line, and it is what the card is for. Summary is
    // the fallback for anything that has no rule.
    summary: plain(data.rule || data.summary),
    category: data.category,
    snark: plain(data.snark),
  });

  const png = new Resvg(svg, {
    fitTo: { mode: "width", value: W },
    font: { fontFiles, loadSystemFonts: false, defaultFontFamily: "Inter" },
  })
    .render()
    .asPng();

  fs.writeFileSync(path.join(OUT, `${slug}.png`), png);
  written++;
}

// Home card, used for / and as the fallback anywhere a page has no image.
const homeSvg = card({
  title: "OMG STOP",
  summary: "Things people keep getting wrong, explained once.",
  category: "Grammar · Spelling · Phrases · Logic",
  snark: "Somebody had to say it.",
});
fs.writeFileSync(
  path.join(OUT, "_default.png"),
  new Resvg(homeSvg, {
    fitTo: { mode: "width", value: W },
    font: { fontFiles, loadSystemFonts: false, defaultFontFamily: "Inter" },
  })
    .render()
    .asPng()
);

console.log(`og: ${written} card(s) + default → _site/og/`);

// ---------------------------------------------------------------- icons ----
// PNG icons for the surfaces that will not take an SVG: iOS home screen,
// Android install prompts, and older link unfurlers. Rendered from the same
// favicon source so they cannot drift from it.
const faviconSvg = fs.readFileSync(path.join(ROOT, "src", "static", "favicon.svg"), "utf8");
for (const size of [180, 192, 512]) {
  const png = new Resvg(faviconSvg, { fitTo: { mode: "width", value: size } })
    .render()
    .asPng();
  fs.writeFileSync(path.join(ROOT, "_site", `icon-${size}.png`), png);
}
console.log("icons: 180, 192, 512 → _site/");
