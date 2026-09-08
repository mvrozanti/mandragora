# `hub/` — landing page + apex redirect + every hub vhost's Caddy labels

Stack for `hub.mvr.ac` and the legacy `*.mvrozanti.duckdns.org` →
`*.mvr.ac` redirect fan-out. Also carries every Caddy reverse-proxy
label for desktop-backed services (ttyd, slither, grafana, myMPD,
rgb-control, im-gen-web, open-webui), since caddy-docker-proxy reads
labels off any container on `seafile-net`. `log.mvr.ac` used to live
here too but moved to its own `logs/` stack when the custom UI
landed.

## Container

| Container | Image | Hosts |
|---|---|---|
| `hub` | `nginx:stable-alpine` | `hub.mvr.ac` (static button grid) + all duckdns→mvr.ac 302 redirects + label-only Caddy entries for `term./slither./grafana./mpd./rgb./gen./llama./claude.mvr.ac` |

Replaced the previous `gethomepage/homepage` container — the YAML-
dashboard model was overkill for what is functionally a list of
links. `nginx:alpine` serving a single static HTML file is
~7 MB image + zero runtime config.

## Live location on VPS

`/home/opc/hub/` — bring up with:
```
cd /home/opc/hub && sudo docker compose up -d
```

Joins the existing `seafile-net` (declared `external: true`) so caddy
sees the labels.

## Static UI

`static/` is bind-mounted into nginx at `/usr/share/nginx/html`. Edit
and refresh — nginx serves the mounted files directly, no restart
needed for content changes.

| File | Layer | Reusable |
|---|---|---|
| `theme.css` | design tokens (`--mv-*`) + baked fallback palette | **yes** |
| `components.css` | the `.mv-*` component vocabulary | **yes** |
| `theme.js` | reads `/api/theme`, applies + caches the matugen palette | **yes** |
| `hub.css` | page frame for this page only | no |
| `hub.js` | renders the hub from `services.json` | no |
| `services.json` | the inventory — one source of truth | no |
| `index.html` | markup skeleton, ~50 lines | no |

The page is the **V1 "field"** direction: one flat list — no section
headers, the way the old tile grid had none — where the machine that
answers for a service is carried as a colour stripe rather than as
position, and the two host panels compress into a collapsible status
band. Topic lives in the filter chips instead of in headings, so
grouping is available on demand without costing vertical space.
Services reachable without signing in carry an open padlock; everything
else is gated and unmarked, because the gate is the default. Mobile-first — the band is a `<details>` that starts closed
below 760px, the chip row scrolls horizontally, rows are 48px tap
targets, and the search field is `16px` so iOS does not zoom on focus.

A row is three marks and nothing else: a health dot, a lock badge, and
the hostname. Public services carry a filled accent badge; gated ones a
dim outlined box, so the badge column reads as a strip. Names and
descriptions are gone — the hostname is the name.

### Health probes, and what green actually means

`host-stats` probes every entry in `services.json` once a minute (6 at a
time, 8s timeout, one retry) and serves the result at `/api/health`. It
probes the **public hostname over HTTPS**, so it exercises the real path:
DNS, TLS, the Caddy route, and Authelia.

| result | state |
|---|---|
| 2xx, 3xx, **401, 403** | ok |
| other 4xx | warn |
| 5xx, or a connection error twice running | down |
| slower than `PROBE_SLOW_MS` (5s) | warn |

**401 and 403 count as healthy.** Authelia answers 401 to anything that
does not look like a browser navigation, so a gated vhost returning 401
means the gate is alive and doing its job. Latency deliberately does not
drive state: the probe reaches the VPS's own public IP through hairpin
NAT, and a cold start can push a whole round past any sane threshold —
the first round after a container restart produced 32 false warnings
before this was fixed. `ms` is still reported, just not acted on.

**The honest limit:** Authelia's `forward_auth` runs *before* the
`reverse_proxy`, so for the 35 gated services a 401 is returned without
the upstream ever being contacted. Green therefore means *the front door
answers*, not *the container behind it is alive*. It reliably catches a
dead VPS, an expired cert, a missing route, a 404 path and any problem on
the 10 public services end-to-end. Catching a dead upstream behind the
gate needs a second probe against the container on `seafile-net`, which
would mean carrying each service's upstream address in `services.json`.

A service whose root is not a sensible health target can name one:
`"probe": "/healthz"` — `api.mvr.ac` uses this, because its root is a
FastAPI 404 by design.

### Colours come from `setbg`

`setbg` runs matugen over the wallpaper and fans the result into kitty,
waybar, mako, rofi, tmux, cava, hyprland and the keyboard LEDs. The hub
joins that fan-out instead of holding its own opinion:

```
setbg → matugen → ~/.cache/matugen/hub-theme.json   (templates/hub-theme.json)
                → gpu-status :6684  GET /api/theme
                → hub.mvr.ac/api/theme  (caddy_0.0_@desk_api)
                → theme.js sets --mv-* on :root, caches in localStorage
```

The desktop is the only machine that knows the wallpaper, and it was
already answering `/api/gpu` over the tailnet, so this is an endpoint,
not a component. When mandragora is asleep the hub keeps the last
palette it saw; `theme.css` carries a baked default for a cold browser.

`theme.js` follows `setbg` **live**: it polls every 5s while the tab is
visible (`data-poll="<seconds>"`, `0` disables), and re-fetches
immediately on focus, tab-visibility and bfcache restore — so the common
case, running `setbg` and alt-tabbing to the browser, repaints on
arrival rather than on a timer. It only touches the DOM when the payload
actually changes, and emits a `mv-theme` event on `window` with the new
palette so a page with charts or a canvas can redraw:

```js
window.addEventListener("mv-theme", function (e) { redraw(e.detail.primary); });
```

**State colours are never themed.** matugen's own `error` token can
collide with its `primary` (under a rose wallpaper both land on
`#ffb3af`), so `--mv-ok` / `--mv-warn` / `--mv-down` are fixed
constants, and state is additionally encoded in *form* — filled dot,
hollow ring, filled dot with a halo plus a tinted row.

### Adopting the system in another service

The three reusable files are self-contained, prefixed `--mv-` / `.mv-`
so they cannot collide, and have no dependencies. To adopt:

1. Copy `theme.css`, `components.css` and `theme.js` into the service.
2. Link them, then point `theme.js` at the hub, which is the only host
   that proxies the desktop:

   ```html
   <link rel="stylesheet" href="theme.css">
   <link rel="stylesheet" href="components.css">
   <script src="theme.js"
           data-endpoint="https://hub.mvr.ac/api/theme"
           data-credentials="include"></script>
   ```

   Same-origin (the hub itself) needs neither attribute. `gpu-status`
   answers CORS for any `https://*.mvr.ac` origin with credentials, so
   the Authelia session cookie carries; a service that is not logged in
   silently keeps the baked palette.
3. Build the page out of `.mv-topbar`, `.mv-card`, `.mv-meter`,
   `.mv-pill`, `.mv-dot`, `.mv-lock`, `.mv-alert`, `.mv-search`,
   `.mv-chip`, `.mv-group`, `.mv-row`, `.mv-legend`, `.mv-footer`.
   (`.mv-group` is vocabulary the hub itself no longer uses — a service
   with fewer, longer lists still wants headed sections.) Anything the
   service needs beyond those belongs in its own stylesheet, not in
   `components.css` — until two services need it, at which point it is
   promoted.

Rule of thumb: a service should never declare a raw hex. If it needs a
colour that is not a `--mv-*` token, that is a gap in the token set.

## Caddy labels carried by this container

The `hub` container's `labels:` block in `docker-compose.yml` is
the dispatch table for the entire hub:

| Label index | Vhost | Behavior |
|---|---|---|
| `caddy_0` | `hub.mvr.ac` | forward_auth → reverse_proxy nginx:80 (the hub UI itself) |
| `caddy_1` | `term.mvr.ac` | forward_auth → reverse_proxy `host.docker.internal:7681` (ttyd, HTTP/1.1) |
| `caddy_2` | `slither.mvr.ac` | path whitelist (`/`, `/simulator.html`, `/favicon.ico`, `/static/*`, `/exported_agents/*`, `/api/*`) → forward_auth → reverse_proxy `host.docker.internal:8088` |
| `caddy_3` | `grafana.mvr.ac` | forward_auth → reverse_proxy `host.docker.internal:3000` |
| `caddy_4` | `mpd.mvr.ac` | forward_auth → reverse_proxy `host.docker.internal:6680` (myMPD on desktop) |
| `caddy_5` | `rgb.mvr.ac` | forward_auth → reverse_proxy `host.docker.internal:6681` (rgb-control on desktop) |
| `caddy_6` | `gen.mvr.ac` | forward_auth → reverse_proxy `host.docker.internal:6682` (im-gen-web on desktop) |
| `caddy_7` | `chat.mvr.ac` | forward_auth → reverse_proxy `host.docker.internal:6683` (open-webui on desktop, `flush_interval=-1` for SSE streaming) |
| `caddy_8` | `claude.mvr.ac` | tailnet IP gate → forward_auth → reverse_proxy `host.docker.internal:7682` (claude-web — aiohttp dir picker that adds a tmux+claude window to the user's current session; no in-browser shell) |
| `caddy_10` | `lens.mvr.ac` | forward_auth → reverse_proxy `host.docker.internal:7683` (cc-lens — Next.js analytics dashboard over `~/.claude`) |
| `caddy_20`–`caddy_29` | `*.mvrozanti.duckdns.org` | 302 redirect to `*.mvr.ac` equivalent (legacy aliases) |

Desktop-backed targets (`term./slither./grafana./mpd./rgb./gen./chat./claude./lens.`)
reach the desktop via `socat-tailnet@<port>.service` on the VPS host
forwarding `127.0.0.1:<port>` → `100.115.80.79:<port>` (mandragora
desktop tailnet IP). Caddy resolves `host.docker.internal` to the
bridge gateway via `extra_hosts` declared in `seafile/caddy.yml`.

## Env

`.env` in this directory (root-owned, gitignored) holds:
- `HUB_HOSTNAME` (default: `hub.mvrozanti.duckdns.org`) — only used
  by the legacy redirect labels; canonical hub is `hub.${MVR_AC}`.
- `SEAFILE_SERVER_HOSTNAME` (default: `mvrozanti.duckdns.org`) — legacy alias root.
- `MVR_AC` (default: `mvr.ac`) — canonical domain.
- `HUB_IMAGE`, `HUB_STATIC_VOLUME` — image/volume overrides.

## DNS records for `mvr.ac`

| Host | Type | Value | Purpose |
|---|---|---|---|
| `mvr.ac` (apex) | A | `185.199.108.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | A | `185.199.109.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | A | `185.199.110.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | A | `185.199.111.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | AAAA | `2606:50c0:8000::153` (and `8001`/`8002`/`8003::153`) | optional IPv6 to GH Pages |
| `www` | CNAME | `mvrozanti.github.io.` | GH redirects www→apex |
| `*` | A | `129.148.45.172` | wildcard → Oracle VPS (covers every `<svc>.mvr.ac`) |

The wildcard `*` keeps the registrar config short — every new
subdomain we add to the hub Just Works without touching DNS.

The apex (`mvr.ac` itself) is **not** routed through Caddy on the
VPS — it goes directly to GitHub Pages. The CNAME file in the
`mvrozanti.github.io` repo's `public/` directory makes Pages claim
the custom domain.
