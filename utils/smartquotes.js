// Curly quotes and apostrophes for anything the reader sees.
//
// Shared by eleventy.config.js (page rendering) and utils/og/generate.js
// (preview cards) so a title cannot come out typographically correct on the
// page and wrong on the card someone actually sees in Slack.
//
// Tag-aware: some fields legitimately contain <em>/<b>, and curling a quote
// inside an HTML attribute would corrupt the markup, so text inside angle
// brackets passes through untouched.
export function smartquotes(input) {
  return String(input ?? "")
    .split(/(<[^>]*>)/)
    .map((chunk, i) => {
      if (i % 2) return chunk; // odd chunks are the tags themselves
      return (
        chunk
          // Elisions and decades first — '90s, 'em, 'til — else the
          // opening-single rule below would treat them as an open quote.
          .replace(/'(?=\d{2}s\b)/g, "’")
          .replace(/(^|[\s([{])'(?=(?:em|til|tis|round)\b)/gi, "$1’")
          // Opening double: at a boundary. Everything left over closes.
          .replace(/(^|[\s([{—–])"/g, "$1“")
          .replace(/"/g, "”")
          // Opening single at a boundary; every remaining ' is an apostrophe.
          .replace(/(^|[\s([{—–])'/g, "$1‘")
          .replace(/'/g, "’")
      );
    })
    .join("");
}
