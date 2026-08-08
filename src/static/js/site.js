// The only JavaScript on the site. It ships from src/static/js/, which the
// passthrough copy in eleventy.config.js maps to the web root, so this file is
// served at /js/site.js with no build step and no bundler.
//
// One file for both features rather than one each: it detects what is on the
// page and initialises only that, and a single request stays cached across
// every entry someone reads in a row.
//
// Nothing here is required for the page to work. base.njk adds `js` to <html>
// before first paint and the CSS keeps every control below display:none until
// then, so with scripting off the share row and the toolbar are simply absent
// rather than present and inert.
(function () {
  "use strict";

  // Lowercase, then flatten the curly quotes smartquotes() put in. Titles
  // render as "its / it’s" with U+2019, and someone typing it's with a straight
  // apostrophe has to find it.
  //
  // Both steps are 1:1 in length, which is the property the highlighter relies
  // on: an index found in the folded string points at the same character in the
  // original. Deliberately no NFD/diacritic pass—that changes length and would
  // break exactly that, and there are no diacritics in this content anyway.
  function fold(text) {
    return String(text)
      .toLowerCase()
      .replace(/[‘’]/g, "'")
      .replace(/[“”]/g, '"');
  }

  /* ---------------------------------------------------------------------------
     Share
     --------------------------------------------------------------------------- */

  function initShare(root) {
    // Read from the metadata base.njk already emits rather than repeating the
    // URL in a data- attribute: canonical is absolute and already respects
    // site.urlStyle, and og:title has been through smartquotes.
    var canonical = document.querySelector('link[rel="canonical"]');
    var ogTitle = document.querySelector('meta[property="og:title"]');
    var url = canonical ? canonical.href : location.href;
    var title = ogTitle ? ogTitle.content : document.title;

    var copyButton = root.querySelector("[data-copy]");
    var copyLabel = root.querySelector("[data-copy-label]");
    var shareButton = root.querySelector("[data-share]");
    var status = root.querySelector(".share__status");
    var revert;

    function flash(message) {
      copyLabel.textContent = message;
      status.textContent = message;
      // Without this a second click inside the window would let the first
      // timer fire early and strand the label back at "Copy link".
      clearTimeout(revert);
      revert = setTimeout(function () {
        copyLabel.textContent = "Copy link";
        status.textContent = "";
      }, 2000);
    }

    // localhost counts as a secure context, so this is also the branch that
    // runs under `npm run dev`.
    function write() {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        return navigator.clipboard.writeText(url);
      }
      return Promise.reject();
    }

    // execCommand is deprecated, but it is the only thing left when the page is
    // not a secure context—reaching the dev server by LAN IP, say.
    function writeFallback() {
      var field = document.createElement("textarea");
      var ok = false;
      field.value = url;
      field.setAttribute("readonly", "");
      field.style.position = "fixed";
      field.style.top = "-9999px";
      document.body.appendChild(field);
      field.select();
      try {
        ok = document.execCommand("copy");
      } catch (error) {
        ok = false;
      }
      document.body.removeChild(field);
      return ok;
    }

    copyButton.addEventListener("click", function () {
      write().then(
        function () {
          flash("Copied.");
        },
        function () {
          flash(writeFallback() ? "Copied." : "Copy it out of the address bar.");
        }
      );
    });

    // Only surfaced where it exists. A Share button that does nothing on the
    // desktop is worse than no Share button.
    if (navigator.share) {
      shareButton.hidden = false;
      shareButton.addEventListener("click", function () {
        // Dismissing the sheet rejects with AbortError. That is not an error.
        navigator.share({ title: title, url: url }).catch(function () {});
      });
    }
  }

  /* ---------------------------------------------------------------------------
     Dashboard search + category filter
     --------------------------------------------------------------------------- */

  function initToolbar(toolbar) {
    var input = toolbar.querySelector(".toolbar__input");
    var chips = Array.prototype.slice.call(toolbar.querySelectorAll(".toolbar__chip"));
    var status = toolbar.querySelector(".toolbar__status");
    var empty = document.querySelector("[data-empty]");
    var sections = Array.prototype.slice.call(document.querySelectorAll(".group"));
    var originals = new WeakMap();
    var items = [];
    var query = "";
    var cat = "all";
    var announce;

    sections.forEach(function (section) {
      var rows = section.querySelectorAll(".peeve-list__item");
      Array.prototype.forEach.call(rows, function (row) {
        var label = row.querySelector(".peeve-list__label");
        var slug = row.querySelector(".peeve-list__slug");
        var summary = row.querySelector(".peeve-list__summary");
        // Only pure-text leaves. Rewriting .peeve-list__title itself would
        // destroy the slug span nested inside it.
        var leaves = [label, slug, summary].filter(Boolean);

        leaves.forEach(function (leaf) {
          originals.set(leaf, leaf.textContent);
        });

        items.push({
          row: row,
          cat: section.dataset.cat,
          leaves: leaves,
          // Folded once, here. 80 prebuilt strings is why per-keystroke
          // filtering needs no debounce—the work is an indexOf per item.
          hay: fold(
            [
              label ? label.textContent : "",
              slug ? slug.textContent : "",
              summary ? summary.textContent : "",
              row.dataset.aliases || ""
            ].join(" ")
          )
        });
      });
    });

    function escapeHtml(text) {
      return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Rebuilt from the cached plain text every time. The query is used only to
    // locate indices and is never inserted, and everything that does get
    // inserted is escaped first, so there is no path from the input box into
    // the DOM as markup.
    function paint(leaf, tokens) {
      var text = originals.get(leaf);
      var folded;
      var hits = [];
      var html = "";
      var cursor = 0;

      if (!tokens.length) {
        reset(leaf);
        return;
      }

      folded = fold(text);
      // toLowerCase can change length on a handful of exotic characters. If it
      // has, the indices below point at the wrong places—leave the row plain.
      // It still matched; it just does not get highlighted.
      if (folded.length !== text.length) {
        reset(leaf);
        return;
      }

      tokens.forEach(function (token) {
        var from = 0;
        var at = folded.indexOf(token, from);
        while (at !== -1) {
          hits.push([at, at + token.length]);
          from = at + token.length;
          at = folded.indexOf(token, from);
        }
      });

      if (!hits.length) {
        reset(leaf);
        return;
      }

      hits.sort(function (a, b) {
        return a[0] - b[0];
      });

      hits.forEach(function (hit) {
        // Overlapping tokens—"it" and "its"—would otherwise nest <mark>s.
        var start = Math.max(hit[0], cursor);
        if (start >= hit[1]) return;
        html += escapeHtml(text.slice(cursor, start));
        html += "<mark>" + escapeHtml(text.slice(start, hit[1])) + "</mark>";
        cursor = hit[1];
      });

      html += escapeHtml(text.slice(cursor));
      leaf.innerHTML = html;
    }

    // textContent reads identically with or without the <mark> wrappers, so it
    // cannot be the test for "has this been painted". An element child is the
    // only reliable sign, and skipping the write when there is none keeps the
    // common case—every row, every keystroke—free of pointless DOM churn.
    function reset(leaf) {
      if (leaf.firstElementChild) leaf.textContent = originals.get(leaf);
    }

    function apply() {
      var tokens = query ? fold(query).split(/\s+/).filter(Boolean) : [];
      var filtering = tokens.length > 0 || cat !== "all";
      var shown = 0;

      items.forEach(function (item) {
        // Chips and the query are ANDed. Picking a category does not throw the
        // query away, and typing does not throw the category away.
        var hit =
          (cat === "all" || item.cat === cat) &&
          tokens.every(function (token) {
            return item.hay.indexOf(token) !== -1;
          });

        item.row.hidden = !hit;
        if (hit) shown += 1;
        item.leaves.forEach(hit ? function (leaf) { paint(leaf, tokens); } : reset);
      });

      // A section with nothing left would otherwise render as a heading
      // floating over an empty list.
      sections.forEach(function (section) {
        section.hidden = !section.querySelector(".peeve-list__item:not([hidden])");
      });

      chips.forEach(function (chip) {
        chip.setAttribute("aria-pressed", String(chip.dataset.cat === cat));
      });

      if (empty) empty.hidden = shown !== 0;

      // The count is the one thing worth debouncing. Filtering is fast enough
      // to run per keystroke, but a live region firing per keystroke reads the
      // whole running tally out loud.
      clearTimeout(announce);
      announce = setTimeout(function () {
        status.textContent = filtering ? shown + " of " + items.length : "";
      }, 400);
    }

    // The premise of the site is that you send someone a link. A filtered view
    // you cannot send is off-premise, so the state rides in the query string.
    function remember() {
      var params = new URLSearchParams();
      var search;
      if (query) params.set("q", query);
      if (cat !== "all") params.set("cat", cat);
      search = params.toString();
      history.replaceState(null, "", search ? "?" + search : location.pathname);
    }

    function restore() {
      var params = new URLSearchParams(location.search);
      var wanted = params.get("cat");
      query = params.get("q") || "";
      if (wanted && chips.some(function (chip) { return chip.dataset.cat === wanted; })) {
        cat = wanted;
      }
      input.value = query;
    }

    input.addEventListener("input", function () {
      query = input.value.trim();
      apply();
      remember();
    });

    input.addEventListener("keydown", function (event) {
      if (event.key !== "Escape" || !input.value) return;
      input.value = "";
      query = "";
      apply();
      remember();
    });

    chips.forEach(function (chip) {
      chip.addEventListener("click", function () {
        cat = chip.dataset.cat;
        apply();
        remember();
      });
    });

    // "/" focuses the search box everywhere else on the web.
    document.addEventListener("keydown", function (event) {
      var active = document.activeElement;
      if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return;
      if (active && /^(INPUT|TEXTAREA|SELECT)$/.test(active.tagName)) return;
      event.preventDefault();
      input.focus();
    });

    restore();
    // Not followed by remember() on purpose: rewriting the URL on load would
    // strip whatever else is on it, campaign parameters included.
    apply();
  }

  var share = document.querySelector(".share");
  var toolbar = document.querySelector(".toolbar");
  if (share) initShare(share);
  if (toolbar) initToolbar(toolbar);
})();
