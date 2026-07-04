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

`static/index.html` is bind-mounted into nginx at
`/usr/share/nginx/html`. Terminal-themed CSS grid of tile buttons;
edit and `docker restart hub` (or just refresh — nginx serves the
mounted file directly, no restart needed for content changes).

Authelia gates the vhost via `forward_auth`, so the page is only
served after a successful login at `auth.mvr.ac`. The visible
buttons all point to other Authelia-gated subdomains; the session
cookie carries through so clicks don't require re-auth.

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
| `*` | A | `146.235.51.189` | wildcard → Oracle VPS (covers every `<svc>.mvr.ac`) |

The wildcard `*` keeps the registrar config short — every new
subdomain we add to the hub Just Works without touching DNS.

The apex (`mvr.ac` itself) is **not** routed through Caddy on the
VPS — it goes directly to GitHub Pages. The CNAME file in the
`mvrozanti.github.io` repo's `public/` directory makes Pages claim
the custom domain.
