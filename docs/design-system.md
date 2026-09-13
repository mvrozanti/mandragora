# Design System — `--mv-*` and the Live Palette

This is the full body of AGENTS.md Rule 20. Read it before adding a
UI to any `*.mvr.ac` host, or when a served page is showing the wrong
colours.

## The system is two files, not one

| File | Role |
|---|---|
| `theme.css` | the `--mv-*` tokens — colour, type scale, spacing, radii, motion |
| `components.css` | the shared primitives built on those tokens (`.mv-card`, `.mv-pill`, `.mv-meter`, …) |

Both are canonical at
[`nix/hosts/mandragora-vps/compose/hub/static/`](../nix/hosts/mandragora-vps/compose/hub/static/)
and copied byte-identically into every other stack. Each stack is its
own container with its own document root, so a copy is unavoidable;
what is avoidable is *drift*, and check `15-design-system-live`
enforces equality against the hub copy.

Per-page CSS (`hub.css`, `watch.css`, `kindle.css`, `skin.css`) layers
on top and may only consume tokens, never redefine them.

## The hex values in `theme.css` are a fallback

This is the part that is easy to get wrong, because the file *looks*
like the source of truth.

`setbg` sets the wallpaper and then runs `matugen`, which regenerates
the whole desktop palette — kitty, waybar, mako, hyprland, tmux,
rofi, cava, keyleds, the RGB chain — from the image's dominant
colour. A served page that hard-codes `#bbcf81` is the one surface
that stops following the machine, and it shows: the phone stays olive
while the desktop went red.

So the flow is:

```
setbg
  └─ matugen ──► ~/.cache/matugen/hub-theme.json    (material roles)
                   │
                   └─ gpu-status :6684  GET /api/theme
                        │
                        └─ socat-tailnet@6684 ──► VPS 172.18.0.1:6684
                             │
                             └─ caddy / nginx ──► same-origin path
                                  │
                                  └─ theme.js ──► root.style.setProperty("--mv-…")
```

`theme.js` maps matugen's Material roles onto the `--mv-*` names —
`surface` → `--mv-bg`, `primary` → `--mv-accent`, and so on — and
writes them as inline custom properties on `:root`, which outrank the
`theme.css` defaults. It caches the last good payload in
`localStorage`, so a page opened while the desktop is asleep still
comes up in the right colours, and falls back to the `theme.css` hex
values only on a truly cold start.

It refreshes on load, on `focus`, and on `pageshow`. Set
`data-poll="N"` for an N-second poll on a dashboard that is left open;
`data-poll="0"` (load-only) is right for anything transient like a
login page.

## Wiring a new UI

```html
<link rel="stylesheet" href="/theme.css" />
<link rel="stylesheet" href="/components.css" />
<script src="/theme.js" data-endpoint="/api/theme" data-poll="0"></script>
```

The endpoint must be **same-origin**. `gpu-status` does send CORS for
`*.mvr.ac`, but a page with a restrictive `connect-src` (Authelia's
is `'self'`) will refuse a cross-origin fetch regardless of what the
server allows — so proxy it into the page's own origin rather than
pointing at `hub.mvr.ac`.

### Gated vs. public surfaces

The hub proxies `/api/theme` behind `forward_auth`. A page that is
shown to an *unauthenticated* visitor cannot use that route, and must
proxy `/api/theme?colors=1` instead:

```nginx
location = /mvr/theme.json {
    proxy_pass http://host.docker.internal:6684/api/theme?colors=1;
    proxy_connect_timeout 2s;
    proxy_read_timeout 3s;
    proxy_intercept_errors on;
    error_page 500 502 503 504 = @palette_offline;
}
location @palette_offline { return 204; }
```

`?colors=1` drops the `wallpaper` key. The full payload carries an
absolute path under `/home/m/`, which confirms the account name — not
a secret, but not something to publish on a login page either.

The `error_page`/`204` fallback matters just as much: the palette
comes from a desktop that is frequently asleep, and no UI may block,
hang, or fail to render because of it. Two-second connect timeout,
degrade silently, let `theme.js` fall back to cache.

The container also needs to reach the bridge:

```yaml
networks:
  - seafile-net
  - tailnet-fwd
extra_hosts:
  - "host.docker.internal:172.18.0.1"
```

## Checking it works

```bash
curl -s http://127.0.0.1:6684/api/theme | head -c 120        # desktop
curl -s http://127.0.0.1:6684/api/theme?colors=1 | grep -c wallpaper   # 0
```

Then load the page, run `setbg`, and refresh it. If the desktop
changed and the page did not, `theme.js` is missing, unreferenced, or
its endpoint is cross-origin.
