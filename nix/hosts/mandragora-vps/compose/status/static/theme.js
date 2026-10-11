(function () {
  var script = document.currentScript;
  var endpoint = (script && script.dataset.endpoint) || "/api/theme";
  var credentials = (script && script.dataset.credentials) || "same-origin";
  var pollSeconds = script && script.dataset.poll !== undefined ? Number(script.dataset.poll) : 5;
  var storageKey = "mv-theme";
  var lastRaw = null;
  var timer = null;

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
    window.dispatchEvent(new CustomEvent("mv-theme", { detail: theme }));
    return true;
  }

  function adopt(raw) {
    if (raw === lastRaw) return;
    var theme;
    try { theme = JSON.parse(raw); } catch (e) { return; }
    if (!apply(theme)) return;
    lastRaw = raw;
    try { localStorage.setItem(storageKey, raw); } catch (e) {}
  }

  function refresh() {
    return fetch(endpoint, { credentials: credentials, cache: "no-store" })
      .then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); })
      .then(adopt)
      .catch(function () {});
  }

  function start() {
    if (timer || !(pollSeconds > 0)) return;
    timer = setInterval(refresh, pollSeconds * 1000);
  }

  function stop() {
    if (!timer) return;
    clearInterval(timer);
    timer = null;
  }

  function wake() {
    if (document.visibilityState === "hidden") { stop(); return; }
    refresh();
    start();
  }

  try {
    var cached = localStorage.getItem(storageKey);
    if (cached) adopt(cached);
  } catch (e) {}

  refresh();
  start();
  document.addEventListener("visibilitychange", wake);
  window.addEventListener("focus", refresh);
  window.addEventListener("pageshow", refresh);

  window.mvTheme = { apply: apply, refresh: refresh, tokens: TOKENS };
})();
