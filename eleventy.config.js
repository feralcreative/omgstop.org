import path from "node:path";
import * as sass from "sass";
import markdownIt from "markdown-it";
import { smartquotes } from "./utils/smartquotes.js";
import { createRequire } from "node:module";

const categories = createRequire(import.meta.url)("./src/_data/categories.json");

// Example notes are authored in front matter, which Eleventy hands back as raw
// strings — the Markdown pipeline only touches the body. Without this, an
// emphasised word in a note ships as literal asterisks.
const md = markdownIt({ html: true, typographer: true });

export default function (eleventyConfig) {
  // Same treatment for Markdown bodies. typographer also handles -- and ...,
  // and it leaves code spans alone.
  eleventyConfig.amendLibrary("md", (mdLib) => mdLib.set({ typographer: true }));
  // SCSS is compiled by Eleventy itself rather than a parallel `sass --watch`
  // process, so `npm run dev` has one watcher and `npm run build` has one step.
  eleventyConfig.addTemplateFormats("scss");
  eleventyConfig.addExtension("scss", {
    outputFileExtension: "css",
    useLayouts: false,

    compile: async function (inputContent, inputPath) {
      const parsed = path.parse(inputPath);

      // Partials (_variables.scss etc.) are pulled in by style.scss; they must
      // not also compile to their own stylesheet in the output.
      if (parsed.name.startsWith("_")) return;

      const result = sass.compileString(inputContent, {
        loadPaths: [parsed.dir || ".", this.config.dir.includes],
        style: "compressed",
      });

      // Lets incremental builds know style.css depends on its partials.
      this.addDependencies(inputPath, result.loadedUrls);

      return async () => result.css;
    },
  });

  eleventyConfig.addPassthroughCopy({ "src/static": "." });
  eleventyConfig.addWatchTarget("./src/css/");

  // Eleventy hands back "/less/"; the whole pitch is that you send someone
  // "omgstop.org/less", so display it that way.
  eleventyConfig.addFilter("prettyUrl", (url) =>
    url.length > 1 ? url.replace(/\/$/, "") : url
  );

  // renderInline, not render: notes sit inside a <p> already, and the block
  // renderer would wrap them in a second one.
  eleventyConfig.addFilter("mdInline", (s) => md.renderInline(String(s ?? "")));
  eleventyConfig.addFilter("smartquotes", smartquotes);

  // Dates for the Atom feed and sitemap. Eleventy sets page.date from the file's
  // committed/created time, which is what "when did this entry appear" means here.
  eleventyConfig.addFilter("isoDate", (d) => new Date(d).toISOString());
  eleventyConfig.addFilter("dateOnly", (d) => new Date(d).toISOString().slice(0, 10));
  eleventyConfig.addFilter("newestPeeveDate", (peeves) => {
    const times = (peeves || []).map((p) => new Date(p.date).getTime()).filter(Boolean);
    return new Date(times.length ? Math.max(...times) : Date.now()).toISOString();
  });

  // Peeves are ordered by the `order` field, then alphabetically, so the index
  // doesn't reshuffle itself every time one gets edited.
  const sortPeeves = (a, b) =>
    (a.data.order ?? 999) - (b.data.order ?? 999) ||
    a.data.title.localeCompare(b.data.title);

  eleventyConfig.addCollection("peeves", (collectionApi) =>
    collectionApi.getFilteredByTag("peeves").sort(sortPeeves)
  );

  // Grouped by category for the index, categories in first-appearance order so
  // `order` controls the sections too rather than an alphabetical accident.
  eleventyConfig.addCollection("peevesByCategory", (collectionApi) => {
    const meta = categories;
    const groups = new Map();
    for (const peeve of collectionApi.getFilteredByTag("peeves").sort(sortPeeves)) {
      const name = peeve.data.category || "Other";
      if (!groups.has(name)) groups.set(name, []);
      groups.get(name).push(peeve);
    }
    return [...groups].map(([name, items]) => {
      const m = meta[name];
      if (!m) {
        // A typo'd category would otherwise silently create an unreachable
        // group with no hub page and no breadcrumb.
        throw new Error(
          `Category "${name}" (${items[0].inputPath}) has no entry in src/_data/categories.json`
        );
      }
      return { name, items, ...m };
    });
  });

  // Same-category siblings, for the "related" block at the foot of each entry.
  // Real internal links between topically-related pages, which is what actually
  // helps crawlers understand a small site — and what stops a reader who landed
  // on one entry from leaving after it.
  eleventyConfig.addFilter("related", function (peeves, currentUrl, category, order, limit) {
    const same = (peeves || []).filter(
      (p) => p.url !== currentUrl && p.data.category === category
    );
    // Start from the current entry's position so each page shows different
    // neighbours rather than every page linking the same first few.
    const idx = same.findIndex((p) => (p.data.order ?? 0) > (order ?? 0));
    const start = idx === -1 ? 0 : idx;
    const out = [];
    for (let i = 0; i < same.length && out.length < (limit || 4); i++) {
      out.push(same[(start + i) % same.length]);
    }
    return out;
  });

  // Category-hub aliases (/logical-fallacies → /fallacies, /eggcorns → /phrases).
  // Same redirect mechanism as peeve aliases, fed from categories.json.
  eleventyConfig.addCollection("categoryAliases", () => {
    const out = [];
    for (const [name, meta] of Object.entries(categories)) {
      for (const slug of meta.aliases || []) {
        out.push({ slug, target: `/${meta.slug}`, title: meta.title });
      }
    }
    return out;
  });

  // Every URL that is not a canonical page: misspellings, category aliases, and
  // whichever of the flat/nested forms is not canonical. All become the same
  // kind of redirect page, so aliases.njk paginates one list.
  //
  // BOTH URL SHAPES ALWAYS EXIST. `site.urlStyle` in src/_data/site.json only
  // decides which one is canonical and which one redirects:
  //
  //   "flat"   (default)  /less           canonical, /grammar/less  redirects
  //   "nested"            /grammar/less   canonical, /less          redirects
  //
  // Flipping that value moves the canonical tag, the sitemap entry, the OG url,
  // the breadcrumb and every internal link together — nothing else to change.
  eleventyConfig.addCollection("allAliases", (collectionApi) => {
    const out = [];
    const seen = new Map();
    const claim = (slug, owner) => {
      if (seen.has(slug)) {
        throw new Error(
          `URL "/${slug}" is claimed by both ${seen.get(slug)} and ${owner}`
        );
      }
      seen.set(slug, owner);
    };

    // Category hubs own /grammar, /fallacies … before anything else can.
    for (const [name, meta] of Object.entries(categories)) {
      claim(meta.slug, `categories.json (${name})`);
    }
    for (const [name, meta] of Object.entries(categories)) {
      for (const slug of meta.aliases || []) {
        claim(slug, `categories.json (${name})`);
        out.push({ slug, target: `/${meta.slug}`, title: meta.title });
      }
    }

    for (const peeve of collectionApi.getFilteredByTag("peeves").sort(sortPeeves)) {
      const canonical = peeve.url.replace(/\/$/, "");
      const cat = categories[peeve.data.category];
      const flat = peeve.fileSlug;
      const nested = `${cat.slug}/${peeve.fileSlug}`;

      // The non-canonical shape redirects to the canonical one.
      const other = canonical === `/${flat}` ? nested : flat;
      claim(other, `${peeve.inputPath} (alternate URL shape)`);
      out.push({ slug: other, target: canonical, title: peeve.data.title });

      for (const slug of peeve.data.aliases || []) {
        claim(slug, peeve.inputPath);
        out.push({ slug, target: canonical, title: peeve.data.title });
      }
    }
    return out;
  });

  return {
    dir: {
      input: "src",
      output: "_site",
      includes: "_includes",
      data: "_data",
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
}
