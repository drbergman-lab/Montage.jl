// Documenter injects custom JS into <head> WITHOUT defer, which this relies
// on: the tier is applied synchronously, before <body> exists, so a reader on
// a shallow tier never sees a flash of prose. The control is built later, on
// DOMContentLoaded.
//
// Layers ride on data-tier-show rather than on class names, because
// Documenter's theme picker assigns document.documentElement.className
// wholesale and would drop anything we added there.

(function () {
  "use strict";

  var KEY = "docs-tier";
  var DEFAULT_TIER = "full";

  // Shallow to deep. Every tier but Code owns one block category, named after
  // it: `!!! tier<id>` in the Markdown, `.is-category-tier<id>` in the CSS,
  // and `data-tier-show~="<id>"` to reveal it. Code is the bare spine, which
  // is never hidden, so it has no category of its own. To add a tier, add a
  // row here and a line to each of the two lists at the top of tiers.css.
  var TIERS = [
    { id: "code", label: "Code", hasBlocks: false, hint: "Code only" },
    { id: "brief", label: "Brief", hasBlocks: true, hint: "A line of orientation, then the code" },
    { id: "full", label: "Full", hasBlocks: true, hint: "The full explanation, then the code" },
    { id: "dev", label: "Dev", hasBlocks: true, hint: "Plus what someone changing it needs" },
    { id: "journal", label: "Journal", hasBlocks: true, hint: "Plus the author's dated notes" }
  ];

  // Nav entries shown only at a given tier or deeper. First match wins, so
  // keep more specific paths first.
  var NAV_GATES = [
    { match: "/dev/journal", tier: "journal" },
    { match: "/dev/", tier: "dev" }
  ];

  var currentIndex = -1;

  function indexOfTier(id) {
    for (var i = 0; i < TIERS.length; i++) { if (TIERS[i].id === id) return i; }
    return -1;
  }

  function stored() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }

  function store(id) {
    try { localStorage.setItem(KEY, id); } catch (e) { /* will not persist */ }
  }

  function initialTier() {
    var fromUrl = null;
    try { fromUrl = new URLSearchParams(window.location.search).get("tier"); } catch (e) {}
    if (indexOfTier(fromUrl) >= 0) return fromUrl;
    var s = stored();
    if (indexOfTier(s) >= 0) return s;
    return DEFAULT_TIER;
  }

  function blockSelector() {
    var parts = [];
    for (var i = 0; i < TIERS.length; i++) {
      if (TIERS[i].hasBlocks) parts.push(".is-category-tier" + TIERS[i].id);
    }
    return parts.join(", ");
  }

  function setTier(id, persist) {
    var idx = indexOfTier(id);
    if (idx < 0) return;
    currentIndex = idx;

    var layers = [];
    for (var i = 0; i <= idx; i++) { if (TIERS[i].hasBlocks) layers.push(TIERS[i].id); }

    var root = document.documentElement;
    root.setAttribute("data-docs-tier", id);
    root.setAttribute("data-tier-show", layers.join(" "));

    if (persist !== false) store(id);
    var input = document.getElementById("docs-tier-" + id);
    if (input) input.checked = true;
    gateNav();
  }

  setTier(initialTier(), true);   // applied immediately, in <head>

  function buildSelector() {
    var wrap = document.createElement("div");
    wrap.className = "docs-tier-selector";
    wrap.setAttribute("role", "radiogroup");
    wrap.setAttribute("aria-label", "Level of detail");

    var title = document.createElement("div");
    title.className = "docs-tier-title";
    title.textContent = "Detail";
    wrap.appendChild(title);

    var options = document.createElement("div");
    options.className = "docs-tier-options";

    TIERS.forEach(function (tier) {
      var input = document.createElement("input");
      input.type = "radio";
      input.name = "docs-tier";
      input.id = "docs-tier-" + tier.id;
      input.value = tier.id;
      input.checked =
        document.documentElement.getAttribute("data-docs-tier") === tier.id;
      input.addEventListener("change", function () {
        if (input.checked) setTier(tier.id, true);
      });

      var label = document.createElement("label");
      label.setAttribute("for", input.id);
      label.title = tier.hint;
      label.textContent = tier.label;

      options.appendChild(input);
      options.appendChild(label);
    });

    wrap.appendChild(options);
    return wrap;
  }

  function mount() {
    if (document.querySelector(".docs-tier-selector")) return;
    var selector = buildSelector();
    var sidebar = document.querySelector("nav.docs-sidebar");

    if (sidebar) {
      var after =
        sidebar.querySelector(".docs-version-selector") ||
        sidebar.querySelector(".docs-package-name");
      if (after && after.parentNode === sidebar) {
        sidebar.insertBefore(selector, after.nextSibling);
      } else {
        sidebar.insertBefore(selector, sidebar.firstChild);
      }
      return;
    }

    // Documenter theme changed, or some other layout: fall back to the top of
    // the article so the control is never stranded.
    var article = document.querySelector("article.content, #documenter-page");
    if (article) article.insertBefore(selector, article.firstChild);
  }

  // Pages that only matter past a certain tier stay out of the sidebar until
  // the reader asks for them. The page you are on is never hidden.
  function gateNav() {
    var links = document.querySelectorAll("nav.docs-sidebar ul.docs-menu a[href]");
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      if (!a.closest) continue;
      var li = a.closest("li");
      if (!li) continue;

      var gate = null;
      for (var g = 0; g < NAV_GATES.length; g++) {
        if (a.pathname.indexOf(NAV_GATES[g].match) !== -1) {
          gate = NAV_GATES[g];
          break;
        }
      }

      var here =
        a.classList.contains("is-active") || a.pathname === window.location.pathname;
      li.classList.toggle("docs-tier-hidden",
        gate !== null && !here && currentIndex < indexOfTier(gate.tier));
    }
  }

  // A search hit or a shared link can point inside a passage the current tier
  // hides. Reveal it for this page view, without changing the saved setting.
  function revealHashTarget() {
    if (!window.location.hash || window.location.hash.length < 2) return;
    var target;
    try {
      target = document.getElementById(
        decodeURIComponent(window.location.hash.slice(1))
      );
    } catch (e) {
      return;
    }
    if (!target || !target.closest) return;
    var box = target.closest(blockSelector());
    if (!box || box.offsetParent !== null) return;
    setTier(TIERS[TIERS.length - 1].id, false);
    box.scrollIntoView();
  }

  function start() {
    mount();
    gateNav();
    revealHashTarget();
    window.addEventListener("hashchange", revealHashTarget);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
