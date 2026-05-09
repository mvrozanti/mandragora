# `hub/` — landing page + apex redirect

Stack for `hub.mvrozanti.duckdns.org` (homepage dashboard) and the
apex `mvrozanti.duckdns.org` redirect to it.

## Containers

| Container | Image | Hosts |
|---|---|---|
| `homepage` | `ghcr.io/gethomepage/homepage:v1.5` | `hub.mvrozanti.duckdns.org` (reverse proxy) + `mvrozanti.duckdns.org` (302→hub) + `gh.mvrozanti.duckdns.org` (302→`mvrozanti.github.io`) |

The redirect labels live on the homepage container itself — no
separate sidecar needed. Apex traffic hits the homepage container's
caddy_1 label, which short-circuits to a 302 before any reverse_proxy
runs, so the homepage backend is never touched for apex requests.

## Live location on VPS

`/home/opc/hub/` — bring up with:
```
cd /home/opc/hub && sudo docker compose up -d
```

Joins the existing `seafile-net` (declared `external: true`) so caddy
sees the labels. Caddy's docker-proxy picks up new label-bearing
containers on the watched network without any caddy restart.

## Config

`config/` is bind-mounted into the homepage container at `/app/config`.
Edit YAML, then `docker restart homepage`. Files:

- `settings.yaml` — site title, layout, theme
- `services.yaml` — link cards
- `bookmarks.yaml` — quick-access bookmarks
- `widgets.yaml` — top-bar widgets (resources, search, datetime)
- `docker.yaml`, `kubernetes.yaml` — empty placeholders (homepage
  expects them present even when unused)
- `custom.css`, `custom.js` — empty hooks for site-wide tweaks

## Env

`.env` in this directory (root-owned, gitignored) holds:
- `HUB_HOSTNAME` (default: `hub.mvrozanti.duckdns.org`)
- `SEAFILE_SERVER_HOSTNAME` (default: `mvrozanti.duckdns.org` — used
  for the apex-redirect label)
- `MVR_AC` (default: `mvr.ac` — vanity domain; subdomains constructed
  as `<svc>.${MVR_AC}` alongside the duckdns equivalents)
- `HOMEPAGE_IMAGE`, `HUB_CONFIG_VOLUME` — image/volume overrides

## DNS records for `mvr.ac`

Set these at the registrar (the rest are tracked here for reference):

| Host | Type | Value | Purpose |
|---|---|---|---|
| `mvr.ac` (apex) | A | `185.199.108.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | A | `185.199.109.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | A | `185.199.110.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | A | `185.199.111.153` | GitHub Pages anycast |
| `mvr.ac` (apex) | AAAA | `2606:50c0:8000::153` (and `8001`/`8002`/`8003::153`) | optional IPv6 to GH Pages |
| `www` | CNAME | `mvrozanti.github.io.` | GH redirects www→apex |
| `*` | A | `146.235.51.189` | wildcard → Oracle VPS (covers hub./seafile./term./paste./slither./grafana./cal.) |

The wildcard `*` keeps the registrar config short — every new
subdomain we add to the hub Just Works without touching DNS.

The apex (`mvr.ac` itself) is **not** routed through Caddy on the
VPS — it goes directly to GitHub Pages. The CNAME file in the
`mvrozanti.github.io` repo's `public/` directory makes Pages claim
the custom domain.
