(function () {
  var script = document.currentScript;
  var endpoint = (script && script.dataset.endpoint) || "/api/theme";
  var credentials = (script && script.dataset.credentials) || "same-origin";
  var storageKey = "mv-theme";

  var TOKENS = {
    surface: "--mv-bg",
    surface_container_low: "--mv-bg-raised",
    surface_container: "--mv-bg-elevated",
    surface_container_high: "--mv-bg-high",
    on_surface: "--mv-text",
    on_surface_variant: "--mv-text-dim",
    outline: "--mv-text-ghost",
    outline_variant: "--mv-line",
    primary: "--mv-accent",
    on_primary: "--mv-on-accent",
    primary_container: "--mv-accent-soft",
    secondary: "--mv-tone-2",
    tertiary: "--mv-tone-3"
  };

  function isHex(v) {
    return typeof v === "string" && /^#[0-9a-f]{3,8}$/i.test(v);
  }

  function apply(theme) {
    if (!theme) return false;
    var root = document.documentElement;
    var applied = 0;
    Object.keys(TOKENS).forEach(function (key) {
      if (isHex(theme[key])) {
        root.style.setProperty(TOKENS[key], theme[key]);
        applied++;
      }
    });
    if (!applied) return false;
    root.style.setProperty("--mv-line-strong", theme.outline || theme.on_surface_variant);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta && isHex(theme.surface)) meta.setAttribute("content", theme.surface);
    return true;
  }

  try {
    apply(JSON.parse(localStorage.getItem(storageKey)));
  } catch (e) {}

  fetch(endpoint, { credentials: credentials, cache: "no-store" })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (theme) {
      if (apply(theme)) {
        try { localStorage.setItem(storageKey, JSON.stringify(theme)); } catch (e) {}
      }
    })
    .catch(function () {});

  window.mvTheme = { apply: apply, tokens: TOKENS };
})();
