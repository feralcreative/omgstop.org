import path from "node:path";
import * as sass from "sass";

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

  // Peeves are ordered by the `order` field, then alphabetically, so the index
  // doesn't reshuffle itself every time one gets edited.
  eleventyConfig.addCollection("peeves", (collectionApi) =>
    collectionApi
      .getFilteredByTag("peeves")
      .sort(
        (a, b) =>
          (a.data.order ?? 999) - (b.data.order ?? 999) ||
          a.data.title.localeCompare(b.data.title)
      )
  );

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
