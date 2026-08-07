import path from "node:path";
import * as sass from "sass";
import markdownIt from "markdown-it";

// Example notes are authored in front matter, which Eleventy hands back as raw
// strings — the Markdown pipeline only touches the body. Without this, an
// emphasised word in a note ships as literal asterisks.
const md = markdownIt({ html: true, typographer: false });

export default function (eleventyConfig) {
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
    const groups = new Map();
    for (const peeve of collectionApi.getFilteredByTag("peeves").sort(sortPeeves)) {
      const name = peeve.data.category || "Other";
      if (!groups.has(name)) groups.set(name, []);
      groups.get(name).push(peeve);
    }
    return [...groups].map(([name, items]) => ({ name, items }));
  });

  // Flattened alias list. A peeve declaring `aliases: [their, there]` gets a
  // redirect page at each, so every spelling someone might guess lands on the
  // same explanation. Kept as its own collection so aliases.njk can paginate
  // one output file per entry.
  eleventyConfig.addCollection("peeveAliases", (collectionApi) => {
    const out = [];
    const seen = new Map();
    for (const peeve of collectionApi.getFilteredByTag("peeves").sort(sortPeeves)) {
      const canonical = peeve.url.replace(/\/$/, "");
      for (const slug of peeve.data.aliases || []) {
        // A slug colliding with a real page would overwrite it, so fail loudly
        // at build time rather than silently shipping a redirect over content.
        if (seen.has(slug)) {
          throw new Error(
            `Alias "${slug}" is claimed by both ${seen.get(slug)} and ${peeve.inputPath}`
          );
        }
        seen.set(slug, peeve.inputPath);
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
